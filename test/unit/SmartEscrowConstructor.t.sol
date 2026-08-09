// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { SmartEscrow } from "../../src/SmartEscrow.sol";
import { Test } from "forge-std/Test.sol";

contract SmartEscrowConstructorTest is Test {
    SmartEscrow internal escrow;

    address internal client = makeAddr("client");
    address internal contractor = makeAddr("contractor");
    address internal arbiter = makeAddr("arbiter");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        escrow = new SmartEscrow(client, contractor, arbiter, 10 ether);
    }

    function test_ConstructorStoresDistinctParties() public view {
        assertEq(escrow.client(), client);
        assertEq(escrow.contractor(), contractor);
        assertEq(escrow.arbiter(), arbiter);
    }

    function test_InitialStateIsCreated() public view {
        assertEq(uint256(escrow.state()), uint256(SmartEscrow.EscrowState.Created));
    }

    function test_PartyLookupFunctionsReturnExpectedValues() public view {
        assertTrue(escrow.isClient(client));
        assertTrue(escrow.isContractor(contractor));
        assertTrue(escrow.isArbiter(arbiter));

        assertFalse(escrow.isClient(outsider));
        assertFalse(escrow.isContractor(outsider));
        assertFalse(escrow.isArbiter(outsider));
    }

    function test_RevertWhenClientIsZeroAddress() public {
        vm.expectRevert(SmartEscrow.ZeroAddress.selector);
        new SmartEscrow(address(0), contractor, arbiter, 10 ether);
    }

    function test_RevertWhenContractorIsZeroAddress() public {
        vm.expectRevert(SmartEscrow.ZeroAddress.selector);
        new SmartEscrow(client, address(0), arbiter, 10 ether);
    }

    function test_RevertWhenArbiterIsZeroAddress() public {
        vm.expectRevert(SmartEscrow.ZeroAddress.selector);
        new SmartEscrow(client, contractor, address(0), 10 ether);
    }

    function test_RevertWhenClientEqualsContractor() public {
        vm.expectRevert(SmartEscrow.DuplicateParty.selector);
        new SmartEscrow(client, client, arbiter, 10 ether);
    }

    function test_RevertWhenClientEqualsArbiter() public {
        vm.expectRevert(SmartEscrow.DuplicateParty.selector);
        new SmartEscrow(client, contractor, client, 10 ether);
    }

    function test_RevertWhenContractorEqualsArbiter() public {
        vm.expectRevert(SmartEscrow.DuplicateParty.selector);
        new SmartEscrow(client, contractor, contractor, 10 ether);
    }
}
