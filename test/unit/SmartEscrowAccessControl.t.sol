// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowAccessControlTest is Test {
    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, 10 ether);
    }

    function test_ClientCanCallClientRestrictedAction() public {
        vm.prank(client);
        assertTrue(escrow.clientRestrictedAction());
    }

    function test_ContractorCanCallContractorRestrictedAction() public {
        vm.prank(contractor);
        assertTrue(escrow.contractorRestrictedAction());
    }

    function test_ArbiterCanCallArbiterRestrictedAction() public {
        vm.prank(arbiter);
        assertTrue(escrow.arbiterRestrictedAction());
    }

    function test_RevertWhenOutsiderCallsClientRestrictedAction() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);
        escrow.clientRestrictedAction();
    }

    function test_RevertWhenOutsiderCallsContractorRestrictedAction() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);
        escrow.contractorRestrictedAction();
    }

    function test_RevertWhenOutsiderCallsArbiterRestrictedAction() public {
        vm.prank(outsider);
        vm.expectRevert(SmartEscrow.Unauthorized.selector);
        escrow.arbiterRestrictedAction();
    }
}
