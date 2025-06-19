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

    function testSubmitTransactionEmitsAndStores() public {
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.SubmitTransaction(0, signer1, recipient, 123);
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

    function testExecuteRevertsAndStateRollback() public {
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.SubmitTransaction(0, signer1, address(reverter), 0);
        multisig.submitTransaction(address(reverter), 0);

        vm.prank(signer2);
        vm.expectRevert(Multisig.ExecFailed.selector);
        multisig.confirmTransaction(0);

        // After revert, state remains
        (, , bool executed, uint confirmations, , , ) = multisig.getTransaction(0);
        assertFalse(executed);
        assertEq(confirmations, 1);
    }

    function testConfirmAndRevokeEvents() public {
        // Submit
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.SubmitTransaction(0, signer1, recipient, 0);
        multisig.submitTransaction(recipient, 0);

        // Revoke
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.RevokeConfirmation(0, signer1);
        multisig.revokeConfirmation(0);

        // Confirm and Execute
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.ConfirmTransaction(0, signer1);
        multisig.confirmTransaction(0);

        vm.prank(signer2);
        vm.expectEmit(true, true, true, true);
        emit Multisig.ExecuteTransaction(0, signer2);
        multisig.confirmTransaction(0);
    }

    function testDoubleConfirmReverts() public {
        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        vm.prank(signer2);
        multisig.confirmTransaction(0);

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

    function testUnauthorizedSubmitAndConfirm() public {
        vm.prank(nonSigner);
        vm.expectRevert(Multisig.NotAuthorised.selector);
        multisig.submitTransaction(recipient, 0);

        vm.prank(signer1);
        multisig.submitTransaction(recipient, 0);
        vm.prank(nonSigner);
        vm.expectRevert(Multisig.NotAuthorised.selector);
        multisig.confirmTransaction(0);
    }

    function testProposeAddSignerEventsAndFlow() public {
        address newSigner = address(0x6);
        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.SubmitTransaction(0, signer1, address(multisig), 0);
        multisig.proposeAddSigner(newSigner);

        (address to, uint value, bool executed, uint confirmations, bool isMgmt, bool add, address target) = multisig.getTransaction(0);
        assertEq(to, address(multisig));
        assertEq(value, 0);
        assertFalse(executed);
        assertEq(confirmations, 1);
        assertTrue(isMgmt && add && target == newSigner);

        vm.prank(signer2);
        vm.expectEmit(true, true, true, true);
        emit Multisig.ExecuteTransaction(0, signer2);
        multisig.confirmTransaction(0);

        assertTrue(multisig.isSigner(newSigner));
        assertEq(multisig.totalSigner(), 4);
        assertEq(multisig.required(), 3);
    }

    function testProposeRemoveSignerEventsAndFlow() public {
        address newSigner = address(0x6);
        vm.prank(signer1);
        multisig.proposeAddSigner(newSigner);
        vm.prank(signer2);
        multisig.confirmTransaction(0);

        vm.prank(signer1);
        vm.expectEmit(true, true, true, true);
        emit Multisig.SubmitTransaction(1, signer1, address(multisig), 0);
        multisig.proposeRemoveSigner(newSigner);

        (address to, uint value, bool executed, uint confirmations, bool isMgmt, bool add, address target) = multisig.getTransaction(1);
        assertEq(to, address(multisig));
        assertEq(value, 0);
        assertFalse(executed);
        assertEq(confirmations, 1);
        assertTrue(isMgmt && !add && target == newSigner);

        vm.prank(signer2);
        vm.expectEmit(true, true, true, true);
        emit Multisig.ConfirmTransaction(1, signer2);
        multisig.confirmTransaction(1);

        vm.prank(signer3);
        vm.expectEmit(true, true, true, true);
        emit Multisig.ExecuteTransaction(1, signer3);
        multisig.confirmTransaction(1);

        assertFalse(multisig.isSigner(newSigner));
        assertEq(multisig.totalSigner(), 3);
        assertEq(multisig.required(), 2);
    }

    function testRevokeNonexistentReverts() public {
        vm.prank(signer1);
        vm.expectRevert(Multisig.TxDoesNotExist.selector);
        multisig.revokeConfirmation(0);
    }

    function testAlreadyConfirmedReverts() public {
        address newSigner = address(0x6);
        vm.prank(signer1);
        multisig.proposeAddSigner(newSigner);
        vm.prank(signer2);
        multisig.confirmTransaction(0);
        vm.prank(signer2);
        vm.expectRevert(Multisig.AlreadyExecuted.selector);
        multisig.confirmTransaction(0);
    }

    function testRemoveBelowMinSignersReverts() public {
        vm.prank(signer1);
        multisig.proposeRemoveSigner(signer3);
        vm.prank(signer2);
        vm.expectRevert(Multisig.NeedsMinSigners.selector);
        multisig.confirmTransaction(0);
    }

    function testFallbackAndReceive() public {
        payable(address(multisig)).transfer(1 wei);
        assertEq(address(multisig).balance, 1 wei + 1 ether);
        (bool ok,) = address(multisig).call("");
        assertTrue(ok);
    }
}
