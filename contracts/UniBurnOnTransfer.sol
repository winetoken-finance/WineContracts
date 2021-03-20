// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/UniswapV2OracleLibrary.sol";

abstract contract UniBurnOnTransfer is ERC20 {
    using SafeMath for uint256;

    /// @notice uniswap listing rate
    uint256 public initialTokensPerEth;

    /// @notice max burn percentage to teach virgins what happens when they sell too early
    uint256 public maxBurnPercent;

    /// @notice min burn percentage
    uint256 public minBurnPercent;

    /// @notice WETH token address
    address public WETH;

    /// @notice self-explanatory
    address public uniswapV2Factory;

    /// @notice liquidity sources (e.g. UniswapV2Router)
    mapping(address => bool) public whitelistedSenders;
    // mapping(address => bool) public whitelistedRecievers;

    /// @notice uniswap pair for Token/ETH
    address public uniswapPair;

    /// @notice Whether or not this token is first in uniswap token<>ETH pair
    bool public isThisToken0;

    /// @notice last TWAP update time
    uint32 public blockTimestampLast;

    /// @notice last TWAP cumulative price
    uint256 public priceCumulativeLast;

    /// @notice last TWAP average price
    uint256 public priceAverageLast;

    /// @notice TWAP min delta (10-min)
    uint256 public minDeltaTwap;

    address private _owner;

    event TwapUpdated(
        uint256 priceCumulativeLast,
        uint256 blockTimestampLast,
        uint256 priceAverageLast
    );

    /**
     * @dev Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(uint256 min, uint256 max, uint256 tokenPerEth) {
        minDeltaTwap = 300; // 5 min
        _owner = msg.sender;
        setWhitelistedSender(address(0), true);
        // setWhitelistedReciever(address(0), true);
        maxBurnPercent = min;
        minBurnPercent = max;
        initialTokensPerEth = tokenPerEth;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "FeeOnTransfer: caller is not the owner");
        _;
    }

    function setUniswapAddresses(address newUniswapV2Factory, address newWeth) external {
       uniswapV2Factory = newUniswapV2Factory;
       WETH = newWeth;
    }

    /**
     * @dev Min time elapsed before twap is updated.
     */
    function setMinDeltaTwap(uint256 _minDeltaTwap) public onlyOwner {
        minDeltaTwap = _minDeltaTwap;
    }

    /**
     * @dev Initializes the TWAP cumulative values for the burn curve.
     */
    function initializeTwap() external onlyOwner {
        require(blockTimestampLast == 0, "twap already initialized");
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(uniswapPair);

        uint256 priceCumulative =
            isThisToken0 ? price1Cumulative : price0Cumulative;

        blockTimestampLast = blockTimestamp;
        priceCumulativeLast = priceCumulative;
        priceAverageLast = initialTokensPerEth;
    }

    /**
     * @dev Sets a whitelisted sender (liquidity sources mostly).
     */
    function setWhitelistedSender(address _address, bool _whitelisted)
        public
        onlyOwner
    {
        whitelistedSenders[_address] = _whitelisted;
    }

    // function setWhitelistedReciever(address _address, bool _whitelisted)
    //     public
    //     onlyOwner
    // {
    //     whitelistedRecievers[_address] = _whitelisted;
    // }

    function initializePair() public onlyOwner {
        (address token0, address token1) =
            UniswapV2Library.sortTokens(address(this), address(WETH));
        isThisToken0 = (token0 == address(this));
        uniswapPair = UniswapV2Library.pairFor(
            uniswapV2Factory,
            token0,
            token1
        );
        setWhitelistedSender(uniswapPair, true);
    }

    function _isWhitelistedSender(address _sender)
        internal
        view
        returns (bool)
    {
        return whitelistedSenders[_sender];
    }

    // function _isWhitelistedReciever(address _sender)
    //     internal
    //     view
    //     returns (bool)
    // {
    //     return whitelistedRecievers[_sender];
    // }

    function _updateTwap() internal virtual returns (uint256) {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(uniswapPair);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed > minDeltaTwap) {
            uint256 priceCumulative =
                isThisToken0 ? price1Cumulative : price0Cumulative;

            // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
            FixedPoint.uq112x112 memory priceAverage =
                FixedPoint.uq112x112(
                    uint224(
                        (priceCumulative - priceCumulativeLast) / timeElapsed
                    )
                );

            priceCumulativeLast = priceCumulative;
            blockTimestampLast = blockTimestamp;

            priceAverageLast = FixedPoint.decode144(
                FixedPoint.mul(priceAverage, 1 ether)
            );

            emit TwapUpdated(
                priceCumulativeLast,
                blockTimestampLast,
                priceAverageLast
            );
        }

        return priceAverageLast;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        
        if (_isWhitelistedSender(sender) && sender == uniswapPair) {
            super._transfer(sender, recipient, amount);
        } else if (_isWhitelistedSender(recipient) && recipient != uniswapPair) {
            super._transfer(sender, recipient, amount);
        } else {
            if (uniswapPair != address(0)) {
                uint256 scaleFactor = 1e18;
                uint256 currentAmountOutPerEth = _updateTwap();
                uint256 currentBurnPct = maxBurnPercent.mul(scaleFactor);
                if (currentAmountOutPerEth < initialTokensPerEth) {
                    // 50 / (initialTokensPerEth / currentAmountOutPerEth)
                    scaleFactor = 1e9;
                    currentBurnPct = currentBurnPct.mul(scaleFactor).div(
                        initialTokensPerEth.mul(1e18).div(
                            currentAmountOutPerEth
                        )
                    );
                    uint256 minBurnPct = (minBurnPercent * scaleFactor) / 10;
                    currentBurnPct = currentBurnPct > minBurnPct
                        ? currentBurnPct
                        : minBurnPct;
                }

                uint256 totalBurnAmount =
                    amount.mul(currentBurnPct).div(100).div(scaleFactor);

                super._burn(sender, totalBurnAmount);

                amount = amount.sub(totalBurnAmount);
            }

            super._transfer(sender, recipient, amount);
        }
            // if (!_isWhitelistedSender(sender)) {
            //     if (uniswapPair != address(0)) {
            //         uint256 scaleFactor = 1e18;
            //         uint256 currentAmountOutPerEth = _updateTwap();
            //         uint256 currentBurnPct = maxBurnPercent.mul(scaleFactor);
            //         if (currentAmountOutPerEth < initialTokensPerEth) {
            //             // 50 / (initialTokensPerEth / currentAmountOutPerEth)
            //             scaleFactor = 1e9;
            //             currentBurnPct = currentBurnPct.mul(scaleFactor).div(
            //                 initialTokensPerEth.mul(1e18).div(
            //                     currentAmountOutPerEth
            //                 )
            //             );
            //             uint256 minBurnPct = (minBurnPercent * scaleFactor) / 10;
            //             currentBurnPct = currentBurnPct > minBurnPct
            //                 ? currentBurnPct
            //                 : minBurnPct;
            //         }

            //         uint256 totalBurnAmount =
            //             amount.mul(currentBurnPct).div(100).div(scaleFactor);

            //         super._burn(sender, totalBurnAmount);

            //         amount = amount.sub(totalBurnAmount);
            //     }
            // }


        // super._transfer(sender, recipient, amount);
    }

    function getCurrentTwap() public view returns (uint256) {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(uniswapPair);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        uint256 priceCumulative =
            isThisToken0 ? price1Cumulative : price0Cumulative;

        FixedPoint.uq112x112 memory priceAverage =
            FixedPoint.uq112x112(
                uint224((priceCumulative - priceCumulativeLast) / timeElapsed)
            );

        return FixedPoint.decode144(FixedPoint.mul(priceAverage, 1 ether));
    }

    function getLastTwap() public view returns (uint256) {
        return priceAverageLast;
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - minted tokens must not cause the total supply to go over the cap.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
    }
}
