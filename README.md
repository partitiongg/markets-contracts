This repo will contain the smart contract code for Partition Markets, a dApp built on top of [Partition Core](https://github.com/partitiongg/core-contracts) to allow Core NFT holders to easily distribute the tokens of their NFT's attached ERC20 contract. [Read this post](https://mirror.xyz/0x211149DE45F8792659312FD505681ff2a0D80599/wB_HBNYQI66BK97mC0Oeh_tg_-LelPGHkupYAhf1EfA) to understand the purpose of all this.

Markets v1.0 is not yet running on Ethereum mainnet, and before it is, we want to receive feedback from interested game developers. The current functionality is described below.


## Activation and initial pool

Markets accept a safeTransferFrom() of a Core NFT, along with encoded configuration data, and `activate` it, producing 1 million coins in the new, specific currency of the ERC20 contract that is now attached to the NFT. It will then deposit a portion of those coins into a pool, for purchase by the public, before transferring the NFT back to the original owner.


## Sale modes

There are three sale *modes* that determine how tokens are priced (in Ether). In each mode, a specified percentage of the tokens created by `activate` are entered into a pool, and the rest are returned to the NFT owner, or the delegate.

**Flat.** The simplest mode. The tokens have a fixed, constant price.

**Linearly increasing.** The tokens increase in price, linearly from a fixed start to a fixed end, as the remaining supply is depleted.

**Dutch auction.** The tokens decrease in price, linearly from a fixed start to a fixed end, as a function of time. An endpoint parameter specifies the future time at which the price will stabilize, and so determines the rate of decrease.


## Pool configuration

It is also possible to create a pool directly, without invoking `activate`. Only a single pool can exist for a given token set, but the configuration options of that pool can be modified at any time by the NFT owner/delegate. A modification to an existing pool - by transferring additional tokens, withdrawing tokens, changing the parameters of the mode, or changing the mode - will place a temporary block on purchases, so buyers have time to notice the change.


## Buyer options

A buyer selects the number of tokens they wish to buy. Only in the case that the price is linearly increasing is an additional parameter needed to ensure fairness: the slippage tolerated by the buyer.
