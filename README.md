This repo contains the smart contract code for Partition Markets, a dApp built on top of [Partition Core](https://github.com/partitiongg/core-contracts) to allow Core NFT holders to easily distribute the tokens of their NFT's attached ERC20 contract.

Markets v0.1 is now running on Goerli testnet at the address [0x8e5891268a9436d7da59ebb39192ebaf4789faf8](https://goerli.etherscan.io/address/0x8e5891268a9436d7da59ebb39192ebaf4789faf8).

## v0.1

Markets accept a safeTransferFrom() of a Core NFT, along with encoded configuration data, and `activate`s it, producing 1 million coins in the new, specific currency of the ERC20 contract that is now attached to the NFT. It then deposits a portion of these coins into a pool for public purchase, and finally transfers the NFT back to its owner.

At any time a pool may be drawn from by a paid call to `purchase(uint256 tokenId, uint256 amount)`. The NFT owner can modify the pool price at any time, and so the outcome of a purchase call is either the caller receives the full amount paid for, or the transaction fails.

It is possible to add tokens to a pool directly, without invoking `activate`. Only a single pool can exist for a given token set, and this pool can also have any amount of its tokens withdrawn at any time by its NFT owner.

All the ETH that has accumulated to a given pool through puchases of its token can transferred at any time to the NFT owner by calling `flush(uint256 tokenId)`.
