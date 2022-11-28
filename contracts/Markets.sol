//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "./IERC721Receiver.sol";
import "./Partition.sol";
import "./TokenStandard.sol";

import "hardhat/console.sol";

contract Markets is IERC721Receiver {
    /* address constant part = 0x8dD5e32685FB2046D20A407da726eb2aeDB1ab64; */
    address constant part = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    enum Mode {Flat, EarlyBird, Dutch}
    // number of tokens in the minimum unit of purchase
    uint128 constant bundle = 1000000000;
    struct Dutch {
        // bundles per wei at start
        uint128 rate;
        // bundles per wei at end
        uint128 rateEnd;
        // increase in rate per second
        uint128 delta;
        // number of tokens offered
        uint128 quantity;
        // number of tokens bought
        uint128 bought;
        // timestamp of dutch start
        uint128 started;
        // if the eth spent on this dutch has been withdrawn
        bool flushed;
        // encodes two uint128s per buyer, one for tokens received, one for wei spent
        mapping(address => uint256) buys;
    }
    struct Pool {
        // current auction mode
        Mode mode;
        // spent on flat and linear
        uint128 spent;
        // number of dutches in token's history
        uint32 numDutches;
        // price for flat and linear
        uint128 rate;
        // slope for linear
        uint128 delta;
        // all dutches in token's history
        mapping(uint32 => Dutch) dutches;
    }
    // 
    mapping(uint256 => Pool) pools;

    event ReturningPaymentB();
    event ReturningPaymentQ();
    
    function getPool(uint256 tokenId) public view returns (Mode, uint128, uint128, uint128, uint32) {
        return (pools[tokenId].mode, pools[tokenId].rate, pools[tokenId].delta, pools[tokenId].spent, pools[tokenId].numDutches);
    }
    
    function getDutch(uint256 tokenId, uint32 dutch) public view returns (uint128, uint128, uint128, uint128, uint128, bool, uint128) {
        Dutch storage dutch = pools[tokenId].dutches[dutch];
        return (dutch.rate, dutch.rateEnd, dutch.delta, dutch.quantity, dutch.bought, dutch.flushed, dutch.started);
    }

    function onERC721Received(address,
                              address from,
                              uint256 tokenId,
                              bytes calldata data
                              ) external override returns (bytes4) {
        require(msg.sender == part);
        
        (address delegate, string memory uri, string memory name, string memory symbol, uint128 keep, bytes memory config) = abi.decode(data, (address,string,string,string,uint128,bytes));
        Partition(part).activate(tokenId, delegate, uri, name, symbol);
        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transfer(from, keep);
        
        newPoolConfig(tokenId, config);
        
        Partition(part).transferFrom(address(this), from, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }

    function newPoolConfigApproved(uint256 tokenId, uint256 amount, bytes memory config) public {
        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transferFrom(msg.sender, address(this), amount);
        newPoolConfig(tokenId, config);
    }

    function newPoolConfig(uint256 tokenId, bytes memory config) public {
        require(msg.sender == part
                || msg.sender == Partition(part).ownerOf(tokenId)
                || msg.sender == Partition(part).getDelegate(tokenId));

        Mode mode = Mode(uint8(config[31]));
        if (mode == Mode.Flat) {
            (uint8 _mode, uint128 rate) = abi.decode(config,(uint8,uint128));
            pools[tokenId].rate = rate;

        } else if (mode == Mode.EarlyBird) {
            (uint8 _mode, uint128 rate, uint128 delta) = abi.decode(config,(uint8,uint128,uint128));
            require(rate > 0 && delta > 0);
            pools[tokenId].rate = rate;
            pools[tokenId].delta = delta;
            
        } else if (mode == Mode.Dutch) {
            if (uint8(config[63]) == 0) {
                (uint8 _mode, uint8 _mod, uint128 rate, uint128 rateEnd, uint128 delta, uint128 quantity) = abi.decode(config,(uint8,uint8,uint128,uint128,uint128,uint128));
                if (pools[tokenId].numDutches > 0) {
                    Dutch storage dutch = pools[tokenId].dutches[pools[tokenId].numDutches-1];
                    require(dutch.bought == dutch.quantity);
                }
                address tAddr = Partition(part).getTokenAddr(tokenId);
                require(quantity <= TokenStandard(tAddr).balanceOf(address(this)));
                require(rate > 0 && rate <= rateEnd);
                require(delta > 0);

                Dutch storage dutch = pools[tokenId].dutches[pools[tokenId].numDutches];
                dutch.rate = rate;
                dutch.rateEnd = rateEnd;
                dutch.delta = delta;
                dutch.quantity = quantity;
                dutch.started = uint128(block.timestamp);
                pools[tokenId].numDutches += 1;
            } else {
                (uint8 _mode, uint8 _mod, uint128 rateEnd, uint128 delta) = abi.decode(config,(uint8,uint8,uint128,uint128));
                Dutch storage dutch = pools[tokenId].dutches[pools[tokenId].numDutches-1];
                require(dutch.bought < dutch.quantity);
                require(dutch.rateEnd <= rateEnd
                        && dutch.delta <= delta);
                dutch.rateEnd = rateEnd;
                dutch.delta = delta;
            }

        }
        pools[tokenId].mode = mode;
    }

    function currentRate(Dutch storage dutch) internal view returns (uint128) {
        uint256 rate = dutch.rate + dutch.delta*(block.timestamp - dutch.started);
        if (rate >= dutch.rateEnd)
            return dutch.rateEnd;
        return uint128(rate);
    }

    function redeem(uint256 tokenId, uint32 dutch) external {
        Dutch storage dutch = pools[tokenId].dutches[dutch];
        uint128 rate = currentRate(dutch);
        if (rate < dutch.rateEnd) {
            require(dutch.bought == dutch.quantity);
            rate = dutch.rate;
        } else if (dutch.bought == dutch.quantity) {
            rate = dutch.rate;
        }

        uint256 buys = dutch.buys[msg.sender];
        uint128 spent = uint128(buys);
        uint128 received = uint128(buys >> 128);
        msg.sender.call{value:spent - received/(rate*bundle) - 1}("");
        dutch.buys[msg.sender] = 0;
    }

    function purchase(uint256 tokenId) external payable {
        Mode mode = pools[tokenId].mode;
        address tAddr = Partition(part).getTokenAddr(tokenId);
        if (mode == Mode.Flat) {
            (uint256 amount) = abi.decode(order, (uint256)); 
            require(msg.value == amount * pools[tokenId].rate);

            pools[tokenId].spent += uint128(msg.value);
            uint128 stack = pools[tokenId].rate*uint128(msg.value)*bundle;
            TokenStandard(tAddr).transfer(msg.sender, amount * bundle);
        } else if (mode == Mode.EarlyBird) {
            uint128 decr = uint128(msg.value)/pools[tokenId].delta;
            if (decr > pools[tokenId].rate)
                decr = pools[tokenId].rate;
            uint128 rate = pools[tokenId].rate-(decr/2);
            uint128 stack = rate*uint128(msg.value)*bundle;
            uint128 bal = uint128(TokenStandard(tAddr).balanceOf(address(this)));
            uint128 toReturn;
            if (stack > bal) {
                toReturn += (stack-bal)/(pools[tokenId].rate*bundle);
                stack = bal;
            }
            if (toReturn > 0)
                msg.sender.call{value:toReturn}("");

            pools[tokenId].rate -= decr;            
            pools[tokenId].spent += uint128(msg.value) - toReturn;
            
            TokenStandard(tAddr).transfer(msg.sender, stack);
        } else if (mode == Mode.Dutch) {
            Dutch storage dutch = pools[tokenId].dutches[pools[tokenId].numDutches-1];
            require(dutch.bought < dutch.quantity);
            uint128 rate = currentRate(dutch);
            uint128 stack = rate*uint128(msg.value)*bundle;
            uint128 bal = uint128(TokenStandard(tAddr).balanceOf(address(this)));
            uint128 toReturn;
            if (stack > bal) {
                emit ReturningPaymentB();
                toReturn += (stack-bal)/(rate*bundle);
                stack = bal;
            }
            if (dutch.bought + stack > dutch.quantity) {
                emit ReturningPaymentQ();
                toReturn += (dutch.bought + stack - dutch.quantity)/(rate*bundle);
                stack = dutch.quantity-dutch.bought;
            }
            if (toReturn > 0)
                msg.sender.call{value:toReturn}("");
            
            uint256 buys = dutch.buys[msg.sender];
            uint128 spent = uint128(buys);
            uint128 received = uint128(buys >> 128);

            spent += uint128(msg.value) - toReturn;
            received += stack;
            buys = spent + (uint256(received) << 128);
            dutch.buys[msg.sender] = buys;
            dutch.bought += uint128(stack);
            if (dutch.bought == dutch.quantity)
                dutch.rate = rate;
                
            TokenStandard(tAddr).transfer(msg.sender, stack);
        }
    }

    function withdraw(uint256 tokenId, uint256 amount) external {
        require(msg.sender == Partition(part).ownerOf(tokenId)
                || msg.sender == Partition(part).getDelegate(tokenId));
        address tAddr = Partition(part).getTokenAddr(tokenId);
        TokenStandard(tAddr).transfer(msg.sender, amount);
    }

    function flushDutch(uint256 tokenId, uint32 dutch) external {
        Dutch storage dutch = pools[tokenId].dutches[dutch];
        require(!dutch.flushed
                && dutch.bought == dutch.quantity);

        address delegate = Partition(part).getDelegate(tokenId);
        if (delegate != address(0))
            payable(delegate).call{value:dutch.bought/(dutch.rate*bundle)}("");
        else
            Partition(part).ownerOf(tokenId).call{value:dutch.bought/(dutch.rate*bundle)}("");
        dutch.flushed = true;
    }
    
    function flush(uint256 tokenId) external {
        address delegate = Partition(part).getDelegate(tokenId);
        if (delegate != address(0))
            payable(delegate).call{value:pools[tokenId].spent}("");
        else
            Partition(part).ownerOf(tokenId).call{value:pools[tokenId].spent}("");
        pools[tokenId].spent = 0;
    }
}
