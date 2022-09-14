//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "./IERC721Receiver.sol";
import "./Partition.sol";
import "./TokenStandard.sol";

import "hardhat/console.sol";

contract Markets is IERC721Receiver {
    address constant part = 0x8dD5e32685FB2046D20A407da726eb2aeDB1ab64;

    struct Pool {
        uint128 price;
        uint128 spent;
    }
    mapping(uint256 => Pool) pools;

    function getPrice(uint256 tokenId) public view returns (uint128) {
        return pools[tokenId].price;
    }
    
    function getSpent(uint256 tokenId) public view returns (uint128) {
        return pools[tokenId].spent;
    }
    
    function onERC721Received(address operator,
                              address from,
                              uint256 tokenId,
                              bytes calldata data
                              ) external override returns (bytes4) {
        require(msg.sender == part);

        (address delegate, string memory uri, string memory name,
         string memory symbol, uint128 keep, uint128 price)
            = abi.decode(data, (address, string, string, string, uint128, uint128));
        Partition(part).activate(tokenId, delegate, uri, name, symbol);


        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transfer(from, keep * 1000000000);
        Partition(part).transferFrom(address(this), from, tokenId);

        pools[tokenId].price = price;
            
        return IERC721Receiver.onERC721Received.selector;
    }
    
    
    function purchase(uint256 tokenId, uint256 amount) external payable {
        // amount is units of 10^9 tokens, so the price is how many wei for 10^9 tokens
        require(msg.value == amount * pools[tokenId].price);
        
        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transfer(msg.sender, amount * 1000000000);
        pools[tokenId].spent += uint128(msg.value);
    }

    function withdraw(uint256 tokenId, uint256 amount) external {
        require(msg.sender == Partition(part).ownerOf(tokenId));
        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transfer(msg.sender, amount);
    }

    function modify(uint256 tokenId, uint128 price) external {
        require(msg.sender == Partition(part).ownerOf(tokenId));
        pools[tokenId].price = price;
    }
    
    function flush(uint256 tokenId) external {
        (bool success, bytes memory data) = Partition(part).ownerOf(tokenId).call{value:pools[tokenId].spent}("");
        require(success);
        pools[tokenId].spent = 0;
    }
}
