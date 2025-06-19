// SPDX-License-Identifier: GNU AFFERO GENERAL PUBLIC LICENSE
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Multisig} from "../src/Multisig.sol";

contract Reverter {
    fallback() external payable {
        revert("fail");
    }
}

contract MultisigTest is Test {
    Multisig multisig;
    Reverter reverter;
    address signer1 = address(0x1);
    address signer2 = address(0x2);
    address signer3 = address(0x3);
    address nonSigner = address(0x4);
    address recipient = address(0x5);

    function setUp() public {
        multisig = new Multisig(signer1, signer2, signer3);
        reverter = new Reverter();
        vm.deal(address(multisig), 1 ether);
    }

    function testInitialSignersAndThreshold() public {
        assertTrue(multisig.isSigner(signer1));
        assertTrue(multisig.isSigner(signer2));
        assertTrue(multisig.isSigner(signer3));
        assertFalse(multisig.isSigner(nonSigner));
        assertEq(multisig.totalSigner(), 3);
        assertEq(multisig.required(), 2);
    }

    function testSubmitTransactionStoresValuesAndMgmtFlags() public {
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 123);

        (address to, uint value, bool executed, uint confirmations, bool isMgmt, bool add, address target) =
            multisig.getTransaction(0);
        assertEq(to, recipient);
        assertEq(value, 123);
        assertFalse(executed);
        assertEq(confirmations, 1);
        assertFalse(isMgmt);
        assertFalse(add);
        assertEq(target, address(0));
    }

    function testExecuteTransactionRevertExecFailed() public {
        vm.prank(signer1);
        multisig.submitTransaction(address(reverter), 0);
        vm.prank(signer2);
        vm.expectRevert(Multisig.ExecFailed.selector);
        multisig.confirmTransaction(0);

        // after revert, confirmations back to 1 and executed false
        (, , bool executed, uint conf, , , ) = multisig.getTransaction(0);
        assertFalse(executed);
        assertEq(conf, 1);
    }

    function testConfirmAndRevokeHappyPath() public {
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        // revoke before second confirmation
        vm.prank(signer1);
        multisig.revokeConfirmation(0);
        (, , bool executed, uint conf, bool isMgmt, bool add, address target) = multisig.getTransaction(0);
        assertFalse(executed);
        assertEq(conf, 0);
        assertFalse(isMgmt);
        assertFalse(add);
        assertEq(target, address(0));

                // confirm twice => executed
        vm.prank(signer1);
        multisig.confirmTransaction(0);
        vm.prank(signer2);
        multisig.confirmTransaction(0);
        {
            (address toOut, uint valueOut, bool executedOut, uint confOut, bool isMgmtOut, bool addOut, address targetOut) = multisig.getTransaction(0);
            assertTrue(executedOut);
            assertEq(confOut, 2);
            assertEq(toOut, recipient);
            assertEq(valueOut, 0);
            assertFalse(isMgmtOut);
            assertFalse(addOut);
            assertEq(targetOut, address(0));
        }
    }

    function testDoubleConfirmReverts() public {
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        vm.prank(signer2);
        multisig.confirmTransaction(0);
        // second confirm hits AlreadyExecuted
        vm.prank(signer2);
        vm.expectRevert(Multisig.AlreadyExecuted.selector);
        multisig.confirmTransaction(0);
    }

    function testRevokeWithoutConfirmReverts() public {
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        vm.prank(signer2);
        vm.expectRevert(Multisig.NotConfirmed.selector);
        multisig.revokeConfirmation(0);
    }

    function testNonSignerCannotSubmitOrConfirm() public {
        vm.prank(nonSigner);
        vm.expectRevert(Multisig.NotAuthorised.selector);
        multisig.submitTransaction(recipient, 0);
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        vm.prank(nonSigner);
        vm.expectRevert(Multisig.NotAuthorised.selector);
        multisig.confirmTransaction(0);
    }

    function testProposeAddSignerFullFlow() public {
        address newSigner = address(0x6);
        vm.prank(signer1);
        multisig.proposeAddSigner(newSigner);
        (address to, uint value, bool executed, uint conf, bool isMgmt, bool add, address target) = multisig.getTransaction(0);
        assertEq(to, address(multisig));
        assertEq(value, 0);
        assertFalse(executed);
        assertEq(conf, 1);
        assertTrue(isMgmt && add && target == newSigner);

        vm.prank(signer2);
        multisig.confirmTransaction(0);
        (to, value, executed, conf, isMgmt, add, target) = multisig.getTransaction(0);
        assertTrue(executed);
        assertEq(conf, 2);
        assertTrue(multisig.isSigner(newSigner));
        assertEq(multisig.totalSigner(), 4);
        assertEq(multisig.required(), 3);
    }

    function testProposeRemoveSignerFullFlow() public {
        address newSigner = address(0x6);
        vm.prank(signer1);
        multisig.proposeAddSigner(newSigner);
        vm.prank(signer2);
        multisig.confirmTransaction(0);

        vm.prank(signer1);
        multisig.proposeRemoveSigner(newSigner);
        (address to, uint value, bool executed, uint conf, bool isMgmt, bool add, address target) = multisig.getTransaction(1);
        assertEq(to, address(multisig));
        assertEq(value, 0);
        assertFalse(executed);
        assertEq(conf, 1);
        assertTrue(isMgmt && !add && target == newSigner);

        // first confirmation
        vm.prank(signer2);
        multisig.confirmTransaction(1);
        // not yet removed and struct fields reflect confirmations
        (to, value, executed, conf, isMgmt, add, target) = multisig.getTransaction(1);
        assertFalse(executed);
        assertEq(conf, 2);

        // second confirmation triggers removal
        vm.prank(signer3);
        multisig.confirmTransaction(1);
        (to, value, executed, conf, isMgmt, add, target) = multisig.getTransaction(1);
        assertTrue(executed);
        assertEq(conf, 3);
        assertFalse(multisig.isSigner(newSigner));
        assertEq(multisig.totalSigner(), 3);
        assertEq(multisig.required(), 2);
    }

    function testProposeAddSignerRevertsForExistingOrZero() public {
        vm.prank(signer1);
        vm.expectRevert(Multisig.SignerExists.selector);
        multisig.proposeAddSigner(signer1);
        vm.prank(signer1);
        vm.expectRevert(Multisig.SignerExists.selector);
        multisig.proposeAddSigner(address(0));
    }

    function testProposeRemoveSignerRevertsForNonSigner() public {
        vm.prank(signer1);
        vm.expectRevert(Multisig.SignerDoesNotExist.selector);
        multisig.proposeRemoveSigner(nonSigner);
    }

    function testRemoveBelowMinSignersRevertsAtExecution() public {
        vm.prank(signer1);
        multisig.proposeRemoveSigner(signer3);
        // proposer auto-confirms (1)
        vm.prank(signer2);
        vm.expectRevert(Multisig.NeedsMinSigners.selector);
        multisig.confirmTransaction(0);
        // after revert, confirmations still 1 and executed false
        (, , bool executed, uint conf, , , ) = multisig.getTransaction(0);
        assertFalse(executed);
        assertEq(conf, 1);
    }

    function testFallbackAndReceive() public {
        payable(address(multisig)).transfer(1 wei);
        assertEq(address(multisig).balance, 1 wei + 1 ether);
        (bool ok,) = address(multisig).call("");
        assertTrue(ok);
    }

    /* ========== ADDITIONAL BRANCH COVERAGE ========== */
    function testRevokeNonexistentReverts() public {
        vm.prank(signer1);
        vm.expectRevert(Multisig.TxDoesNotExist.selector);
        multisig.revokeConfirmation(0);
    }

    function testAlreadyConfirmedRevertsOnSecondConfirmWithoutExecution() public {
        // propose removal of a signer with threshold 3
        address newSigner = address(0x6);
        vm.prank(signer1);
        multisig.proposeAddSigner(newSigner);
        vm.prank(signer2);
        multisig.confirmTransaction(0);
        // Now propose removal at txId=1
        vm.prank(signer1);
        multisig.proposeRemoveSigner(newSigner);
        // first confirmation by signer2
        vm.prank(signer2);
        multisig.confirmTransaction(1);
        // second confirm by same signer2 before threshold -> revert AlreadyConfirmed
        vm.prank(signer2);
        vm.expectRevert(Multisig.AlreadyConfirmed.selector);
        multisig.confirmTransaction(1);
    }

}
