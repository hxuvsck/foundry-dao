// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Timelock} from "../src/Timelock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    Timelock timelock;
    GovToken govToken;


    address public USER = makeAddr("USER");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - after the vote passes

    uint256[] values;
    bytes[] calldatas;
    address[] targets;
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400; // represents 1 week


    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new Timelock(MIN_DELAY, proposers, executors);
        governor - new MyGovernor(govToken, timelock);

        // governor need whole bunch of roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(propserRole, address(governor)); // only the governor can actually proposer stuff
        timelock.grantRole(executorRole, address(0)); // anybody can execute a pass proposal
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock)); // timelock is the ultimate say on where the stuff goes
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;

        string memory description = "store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
       
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // Now we call propose function. This returns proposalId

        //1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        //2. View the state of the proposal
        console.log("Proposal State: ", uint256(governor.state(proposalId))); // in abstract of IGovernor(IERC165), it has enum as (Pending 0, Active 1, Canceled 2 etc...) <<< could be found from state() function of Governor.sol return which is ProposalState

        // It hasn't started due to delay. So we need to update as pass to our testing mock/fake blockchain 

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(governor.state(proposalId))); // now the state should be Active.

        //2. Vote
        string memory reason = "cause 888 is infinity";
        // has vote types as: Against(0), For(1), Abstain(2) in GovernorCountingSimple.sol as every castVote or _castVote function leads to this types.

        uint8 voteWay = 1; //voting yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        //voting period is 1 week as we need to speed it up now.
        
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        //3. Queue the TX / means passed, but have to wait up the same bits of propose function parameters
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        //4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        assert(box.getNumber() ==valueToStore);
        console.log("Box value:", box.getNumber());
    }
}