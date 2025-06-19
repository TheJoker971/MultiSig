// SPDX-License-Identifier: GNU AFFERO GENERAL PUBLIC LICENSE
pragma solidity ^0.8.4;

import {Script, console} from "forge-std/Script.sol";
import {Multisig} from "../src/Multisig.sol";

contract MultisigScript is Script {
    /// @notice Clefs d'env pour les signataires
    string constant SIG1 = "SIGNER1";
    string constant SIG2 = "SIGNER2";
    string constant SIG3 = "SIGNER3";

    function setUp() public {
        // Optionnel : ici, vous pouvez préparer des états ou des mocks
    }

    function run() public {
        // Démarre le broadcast des tx réelles
        vm.startBroadcast();

        // Récupère trois adresses de signataire depuis l'env (export SIGNER1, SIGNER2, SIGNER3)
        address signer1 = vm.envAddress(SIG1);
        address signer2 = vm.envAddress(SIG2);
        address signer3 = vm.envAddress(SIG3);

        // Déploie le wallet multisig
        Multisig wallet = new Multisig(signer1, signer2, signer3);

        // Log l'adresse du contrat déployé
        console.log("Multisig deployed at:", address(wallet));
        console.log("Signers:", signer1, signer2, signer3);

        vm.stopBroadcast();
    }
}
