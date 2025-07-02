### [M-#] Looping though players array to check for duplicate players in `PuppyRaffle::enterRaffle` is a potential Denial of Service (DOS) attack, incrementing gas cost for future raffle entrants.

**Description:** The `PuppyRaffle::enterRaffle` function loops through the `players` array to check for duplicates. However, the longer the `PuppyRaffle::players` array gets, the more checks a new player will have to make, hence making the transaction very expensive to go through. This means the gas cost for players for initally enter the raffle will be dramatically less than those who enter later. Every new address in the `PuppyRaffle::players` array, is an additional check the loop will have to make.

```javascript
//@audit DOS Attack
@> for (uint256 i = 0; i < players.length - 1; i++) {
    for (uint256 j = i + 1; j < players.length; j++) {
        require(players[i] != players[j], "PuppyRaffle: Duplicate player");
    }
 }
```

**Impact:** The gas cost for raffle entrance will greatly increase as more players enter the raffle. Discouraging later users from entering, causing a rush at the start of the raffle to be one of the first entrants in the queue.

An attacker might make the `PuppyRaffle::players` array so big, that no one else enters, guarenteening themselves the win.

**Proof of Concept:**
If fuzz testing is performed with a random number of players in the range of `4 - uint(64).max`, the following test case is expected to fail.

<details>
<summary>POC</summary>
Place the following test into `PuppyRaffleTest.t.sol`

```javascript
function test_Reverts_DOS_Attack_On_Unbounded_For_Loop(uint64 playersCount) external {
    vm.assume(playersCount >= 4 && playersCount <= type(uint64).max);
    address[] memory players = new address[](playersCount);
    for(uint256 i = 0 ; i < playersCount; ++i){
        players[i] = address(uint160(i));
    }
    puppyRaffle.enterRaffle{value: entranceFee * playersCount}(players);
}
```

</details>

**Recommended Mitigation:** There are a few recommendations:

1. Consider allowing duplicates. Users can make new wallet addresses anyway, so a duplicate check doesn't prevent the person from entering multiple times, only the same wallet address.
2. Consider using mapping to check for duplicates. This would allow a constant time lookup of whether a user has already entered.
3. Consider using [`Openzeppelin's Enumerable set library`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol), provides a gas-efficient way to track keys and reset mappings by iterating and deleting entries.
