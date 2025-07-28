#  Engine Contract

The `Engine` contract powers a [Tossoff](https://tossoff.xyz) coin flip game where two players stake equal ETH amounts, and a verifiably random winner is selected using a VRF (Verifiable Random Function) system.



---

##  Features

- **Create & Join Matches:**  
  - Player 1 creates a match by sending ETH.  
  - Player 2 can join by sending the same amount.

- **Verifiable Randomness:**  
  - Once both players join, a random number is requested via an external VRF system.  
  - The winner is decided on-chain using the result.

- **Fees & Payouts:**  
  - A small fee (set by the contract) is deducted from the total pot.  
  - The remaining amount is sent to the winner.  
  - The owner can claim the collected fees.

- **Match Lifecycle Events:**  
  Emits key events for:  
  - Match creation  
  - Match joining  
  - Randomness request  
  - Match completion  
  - Match cancellation

---

##  Contract Setup

- Uses [Solmate](https://github.com/transmissions11/solmate) for modular utilities (`Owned`, `ReentrancyGuard`)  
- Integrates with a custom `IVRFSystem` for randomness by [Proof of play](https://proofofplay.com/). 

---

##  Admin Controls

The contract owner can:  
- Claim accumulated fees  
- Set up the contract at deployment with a valid VRF system

---

##  Match Flow

1. Player 1 creates a match with ETH  
2. Player 2 joins with matching ETH  
3. A randomness request is made  
4. Winner is selected using the random number  
5. Winnings are sent automatically

---

##  Match Cancellation

- A match can be cancelled only by its creator  
- Cancellation is only allowed before the match is joined

---
