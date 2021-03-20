// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./libraries/UniswapV2Library.sol";

import "./interfaces/TokenMinter.sol";

contract TreeToken is Context, AccessControl, ERC721Burnable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    string constant TOKEN_NAME = "Cabernet Franc Tree Token";
    string constant TOKEN_SYMBOL = "CTREE";
    string constant TOKEN_BASEURI = "WINE_FNANCE";
    address public grapeAddress;
    address public boostAddress;
    uint256 public boostTokenForHour = 1 ether;
    uint256 public treePrice;
    uint256 private teamShare;
    address payable private teamAddress;
    uint256 private devShare;
    address payable private devAddress;
    address public uniSwapRouterAddress;
    address public uniSwapFactoryAddress;
    address public wethAddress;

    uint256 public lastLiquidityRemoval;
    uint256 public totalLiquidityAccumulated;
    uint256 public liquidityRemovalTimeLock;

    Counters.Counter private _tokenIdTracker;

    struct Tree {
        uint256 lastAgeUpdate;
        uint256 treeAge;
        bool isAlive;
        uint256 grapeGenerated;
        uint256 boostedAmount;
    }

    mapping(uint256 => Tree) public treeStatus;
    uint256 public currentCap;

    event TreeBurned(
        address indexed from,
        uint256 indexed treeId,
        uint256 grapeCreated
    );

    constructor() ERC721(TOKEN_NAME, TOKEN_SYMBOL) {
        // setting current Cap
        currentCap = 1500;
        treePrice = 500000000000000000; // 0.5 ether
        teamShare = 25000000000000000; // 0.025 ether
        devShare = 25000000000000000; // 0.025 ether
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MODERATOR_ROLE, _msgSender());

        _setBaseURI(TOKEN_BASEURI);

        devAddress = _msgSender();

        liquidityRemovalTimeLock = block.timestamp.add(180 days); // till the next 6 month

        for (uint256 i = 0; i < 12; i++) {
            address mintTo = 0x66a204539A77f9DD9dcB33a88E9C9bB12025235a;
            if (i > 5) {
                mintTo = msg.sender;
            }
            _mint(mintTo, _tokenIdTracker.current());
            // set tree status
            treeStatus[_tokenIdTracker.current()] = Tree({
                lastAgeUpdate: block.timestamp,
                treeAge: 0,
                isAlive: true,
                grapeGenerated: 0,
                boostedAmount: 0
            });
            _tokenIdTracker.increment();
        }

    }

    modifier updateTreeStatus(uint256 treeId) {
        require(treeStatus[treeId].isAlive, "Tree is dead.");
        if (block.timestamp > treeStatus[treeId].lastAgeUpdate) {
            uint256 toBeAddTreeAge = block.timestamp.sub(treeStatus[treeId].lastAgeUpdate);
            treeStatus[treeId].treeAge = treeStatus[treeId].treeAge.add(
                toBeAddTreeAge
            );
            treeStatus[treeId].lastAgeUpdate = block.timestamp;
        }
        _;
    }

    function setTeamDevAddress(
        address payable newTeamAddress,
        address payable newDevAddress
    ) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must have MODERATOR_ROLE do this action"
        );
        teamAddress = newTeamAddress;
        devAddress = newDevAddress;
    }

    function setUniswapAddresses(
        address newRouterAddress,
        address newUniSwapFactoryAddress,
        address newWethAddress
    ) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must have MODERATOR_ROLE do this action"
        );
        uniSwapRouterAddress = newRouterAddress;
        uniSwapFactoryAddress = newUniSwapFactoryAddress;
        wethAddress = newWethAddress;
    }

    function setCap(uint256 newCap) public {
        require(
            totalSupply() <= newCap,
            "TreeToken: hard Cap is lower than current total supply"
        );
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be MODERATOR_ROLE to set hard cap"
        );
        currentCap = newCap;
    }

    function setgrapeAddress(address newgrapeAddress) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be MODERATOR_ROLE to set hard cap"
        );
        grapeAddress = newgrapeAddress;
    }

    function setBoostAddress(
        address newBoostAddress,
        uint256 newBoostTokenForHour
    ) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "CowToken: must be MODERATOR_ROLE to set hard cap"
        );
        boostAddress = newBoostAddress;
        boostTokenForHour = newBoostTokenForHour;
    }

    function setTreePrice(
        uint256 newTreePrice,
        uint256 newTeamShare,
        uint256 newDevShare
    ) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be MODERATOR_ROLE to set hard cap"
        );
        treePrice = newTreePrice;
        teamShare = newTeamShare;
        devShare = newDevShare;
    }

    function buyTrees(uint256 amount) public payable virtual {
        uint256 totalEthInput = treePrice.mul(amount);
        // require(
        //     amount <= 10,
        //     "TreeToken: can not buy more than 10 Trees at once"
        // );
        require(
            msg.value == totalEthInput,
            "TreeToken: not recieved enough eth"
        );

        teamAddress.transfer(teamShare.mul(amount));
        devAddress.transfer(devShare.mul(amount));

        for (uint256 i = 0; i < amount; i++) {
            _mint(msg.sender, _tokenIdTracker.current());
            // set tree status
            treeStatus[_tokenIdTracker.current()] = Tree({
                lastAgeUpdate: block.timestamp,
                treeAge: 0,
                isAlive: true,
                grapeGenerated: 0,
                boostedAmount: 0
            });
            _tokenIdTracker.increment();
        }

        uint256 remainingEth =
            totalEthInput.sub(
                (teamShare.mul(amount).add(devShare.mul(amount)))
            );
        addEthToGrapeLiquidity(remainingEth);
    }

    function getQuote(uint256 ethAmount)
        internal
        view
        returns (uint256 tokenNeeded)
    {
        (uint256 reserveA, uint256 reserveB) =
            UniswapV2Library.getReserves(
                uniSwapFactoryAddress,
                grapeAddress,
                wethAddress
            );
        tokenNeeded = UniswapV2Library.quote(ethAmount, reserveB, reserveA);
    }

    function addEthToGrapeLiquidity(uint256 ethInput) internal {
        require(
            grapeAddress != address(0),
            "TreeToken: grape tree is not set yet."
        );

        // add liquidity for grape
        require(
            ethInput.mul(10000).div(10000) == ethInput,
            "amount of contract eth balance is too low"
        );
        IUniswapV2Router02 router = IUniswapV2Router02(uniSwapRouterAddress);
        uint256 grapeTokenAmount = getQuote(ethInput).add(2 ether);
        TokenMinter(grapeAddress).mint(address(this), grapeTokenAmount);
        IERC20(grapeAddress).approve(uniSwapRouterAddress, grapeTokenAmount);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
            router.addLiquidityETH{value: ethInput}(
                grapeAddress,
                grapeTokenAmount,
                grapeTokenAmount.div(2),
                ethInput,
                address(this),
                block.timestamp.add(1800) // deadline is 30 min
            );

        totalLiquidityAccumulated = totalLiquidityAccumulated.add(liquidity);

        uint256 amountToBurn = IERC20(grapeAddress).balanceOf(address(this));
        TokenMinter(grapeAddress).burn(amountToBurn);
    }

    function removeGrapeLiquidity(address pool, uint256 liquidity) public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be Moderator to handle eth from tree"
        );

        if (block.timestamp <= liquidityRemovalTimeLock) {
            require(lastLiquidityRemoval.add(30 days) <= block.timestamp, "Too soon for removing liquidity");
            require(liquidity <= totalLiquidityAccumulated.mul(5).div(100), "Too much liquidity removal not allowed");
        }
        lastLiquidityRemoval = block.timestamp;

        // approve token
        IERC20(pool).approve(uniSwapRouterAddress, liquidity);

        IUniswapV2Router02 router = IUniswapV2Router02(uniSwapRouterAddress);
        // remove liquidity
        (uint256 amountToken, uint256 amountETH) =
            router.removeLiquidityETH(
                grapeAddress,
                liquidity,
                0,
                0,
                address(this),
                block.timestamp.add(1800)
            );
        totalLiquidityAccumulated = totalLiquidityAccumulated.sub(liquidity);
        // burn token
        TokenMinter(grapeAddress).burn(amountToken);
        // send eth to sender
        address payable owner = payable(_msgSender());
        uint256 contractEthBalance = address(this).balance;
        owner.transfer(contractEthBalance);
    }

    function burnLeftOverGrapeToken() public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be Moderator to handle eth from tree"
        );
        uint256 amountToBurn = IERC20(grapeAddress).balanceOf(address(this));
        TokenMinter(grapeAddress).burn(amountToBurn);
    }

    function withdrawLeftOverEth() public {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "TreeToken: must be Moderator to handle eth from tree"
        );
        address payable owner = payable(_msgSender());
        uint256 contractEthBalance = address(this).balance;
        owner.transfer(contractEthBalance);
    }

    // fallback() external payable {}
    receive() external payable { }

    function updatingTreeAgeStatus(uint256 treeId)
        public
        updateTreeStatus(treeId)
        returns (uint256)
    {
        require(
            ownerOf(treeId) == _msgSender(),
            "TreeToken: You are not the lawful owner of this tree."
        );
        return (treeStatus[treeId].treeAge);
    }

    function getTreePotencial(uint256 treeId)
        public
        view
        returns (
            bool isAlive,
            uint256 potencialGrape,
            uint256 treeAge
        )
    {
        isAlive = treeStatus[treeId].isAlive;
        if (isAlive) {
            treeAge = (block.timestamp.sub(treeStatus[treeId].lastAgeUpdate)).add(
                treeStatus[treeId].treeAge
            );
            uint256 canGenerateGrape = treeAge.div(24); // ~3 day till ~10k
            if (canGenerateGrape > 10000) {
                uint256 fixedLimit = 100;
                potencialGrape = fixedLimit.mul(10**18);
            } else {
                potencialGrape = canGenerateGrape.mul(10**16);
            }
        } else {
            treeAge = treeStatus[treeId].treeAge;
            potencialGrape = treeStatus[treeId].grapeGenerated;
        }
    }

    function burnTreeForGrape(uint256 treeId) public updateTreeStatus(treeId) {
        require(
            ownerOf(treeId) == _msgSender(),
            "TreeToken: You are not the lawful owner of this tree."
        );
        (, uint256 canGenerateGrape, ) = getTreePotencial(treeId);
        treeStatus[treeId].isAlive = false;
        treeStatus[treeId].grapeGenerated = canGenerateGrape;
        TokenMinter(grapeAddress).mint(_msgSender(), canGenerateGrape);
        emit TreeBurned(_msgSender(), treeId, canGenerateGrape);
    }

    function isBosstTreeActive() public view returns (bool) {
        return boostAddress != address(0);
    }

    function boostTree(uint256 treeId, uint256 tokenAmount)
        public
        updateTreeStatus(treeId)
    {
        require(
            boostAddress != address(0),
            "TreeToken: Boost feature is not active yet."
        );
        uint256 treeAge = treeStatus[treeId].treeAge;
        IERC20(boostAddress).transferFrom(
            _msgSender(),
            teamAddress,
            tokenAmount
        );
        uint256 addition = tokenAmount.div(boostTokenForHour).mul(3600);
        treeStatus[treeId].treeAge = treeAge.add(addition);
        uint256 boostedAmount = treeStatus[treeId].boostedAmount;
        treeStatus[treeId].boostedAmount = boostedAmount.add(tokenAmount);
    }

    function boostTreeWithEth(uint256 treeId)
        public
        payable
        updateTreeStatus(treeId)
    {
        require(
            boostAddress == address(0),
            "TreeToken: Boost feature is set to token not eth."
        );
        uint256 treeAge = treeStatus[treeId].treeAge;

        uint256 coinAmount = msg.value;
        address payable devPay = payable(devAddress);
        address payable temaPay = payable(teamAddress);
        temaPay.transfer((msg.value).div(2));
        devPay.transfer(address(this).balance);
        uint256 addition = coinAmount.div(boostTokenForHour).mul(3600);
        treeStatus[treeId].treeAge = treeAge.add(addition);
        uint256 boostedAmount = treeStatus[treeId].boostedAmount;
        treeStatus[treeId].boostedAmount = boostedAmount.add(coinAmount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            // When minting tokens
            require(
                totalSupply().add(1) <= currentCap,
                "TreeToken: cap exceeded"
            );
        }
    }
}
