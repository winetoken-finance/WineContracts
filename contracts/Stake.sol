// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/TokenMinter.sol";

contract Stake is AccessControl {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // models
    struct stakeTracker {
        uint256 lastBlockChecked;
        uint256 rewards;
        uint256 tokenStaked;
        uint256 boostTokenStaked;
    }

    // variables
    uint256 public totalBoostTokenStaked;
    uint256 public totalTokenStaked;
    address public stakedTokenContractAddress;
    address public stakedBoostTokenContractAddress;
    address public stakeRewardTokenContractAddress;
    uint256 public boostScaleFactor;

    mapping(address => stakeTracker) public stakedBalances;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MODERATOR_ROLE, _msgSender());
        boostScaleFactor = 10;
    }

    event Staked(address indexed user, uint256 poolToken, uint256 boostToken);
    event unStaked(address indexed user, uint256 poolToken, uint256 boostToken);
    event Rewards(address indexed user, uint256 reward);

    modifier updateStakingReward(address account) {
        if (block.number > stakedBalances[account].lastBlockChecked) {
            uint256 rewardBlocks =
                block.number.sub(stakedBalances[account].lastBlockChecked);

            if (stakedBalances[account].tokenStaked > 0) {
                stakedBalances[account].rewards = myRewardsBalance(account);
            }
            stakedBalances[account].lastBlockChecked = block.number;
        }
        _;
    }

    function getStakeTokenTotalSupply()
        internal
        view
        returns (uint256 totalSupply)
    {
        totalSupply = IERC20(stakedTokenContractAddress).totalSupply();
    }

    function setBoostScaleFactor(uint256 newFactor) external {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "Stake: must be MODERATOR_ROLE to perfrom this acction"
        );
        boostScaleFactor = newFactor;
    }

    function setStakeTokenContractAddress(address origen) external {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "Stake: must be MODERATOR_ROLE to perfrom this acction"
        );
        stakedTokenContractAddress = origen;
    }

    function setStakedBoostTokenContractAddress(address origen) external {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "Stake: must be MODERATOR_ROLE to perfrom this acction"
        );
        stakedBoostTokenContractAddress = origen;
    }

    function setStakeRewardTokenContractAddress(address destination) external {
        require(
            hasRole(MODERATOR_ROLE, _msgSender()),
            "Stake: must be MODERATOR_ROLE to perfrom this acction"
        );
        stakeRewardTokenContractAddress = destination;
    }

    function myRewardsBalance(address account)
        public
        view
        returns (uint256 estimatedReward)
    {
        if (block.number > stakedBalances[account].lastBlockChecked) {
            uint256 rewardBlocks =
                block.number.sub(stakedBalances[account].lastBlockChecked);

            if (stakedBalances[account].tokenStaked > 0) {
                estimatedReward = stakedBalances[account].rewards.add(
                    (
                        (
                            (
                                stakedBalances[account].tokenStaked.add(
                                    stakedBalances[account].boostTokenStaked.mul(boostScaleFactor)
                                )
                            )
                            .mul(rewardBlocks)
                        )
                            .div(getStakeTokenTotalSupply().div(10**16))
                    )
                );
            } else {
                estimatedReward = 0;
            }
        }
    }

    function stake(uint256 poolTokenAmount, uint256 boostTokenAmount)
        public
        updateStakingReward(_msgSender())
    {
        totalBoostTokenStaked = totalBoostTokenStaked.add(boostTokenAmount);
        totalTokenStaked = totalTokenStaked.add(poolTokenAmount);

        stakedBalances[_msgSender()].tokenStaked = stakedBalances[
            _msgSender()
        ]
            .tokenStaked
            .add(poolTokenAmount);

        stakedBalances[_msgSender()].boostTokenStaked = stakedBalances[
            _msgSender()
        ]
            .boostTokenStaked
            .add(boostTokenAmount);

        if (boostTokenAmount != uint256(0)) {
            IERC20(stakedBoostTokenContractAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                boostTokenAmount
            );
        }

        if (poolTokenAmount != uint256(0)) {
            IERC20(stakedTokenContractAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                poolTokenAmount
            );
        }
        

        emit Staked(_msgSender(), poolTokenAmount, boostTokenAmount);
    }

    function unStake(uint256 poolTokenAmount, uint256 boostTokenAmount)
        public
        updateStakingReward(_msgSender())
    {
        totalBoostTokenStaked = totalBoostTokenStaked.sub(boostTokenAmount);
        totalTokenStaked = totalTokenStaked.sub(poolTokenAmount);

        stakedBalances[_msgSender()].boostTokenStaked = stakedBalances[
            _msgSender()
        ]
            .boostTokenStaked
            .sub(boostTokenAmount);
        stakedBalances[_msgSender()].tokenStaked = stakedBalances[
            _msgSender()
        ]
            .tokenStaked
            .sub(poolTokenAmount);

        if (boostTokenAmount != uint256(0)) {
            IERC20(stakedBoostTokenContractAddress).safeTransfer(
                _msgSender(),
                boostTokenAmount
            );
        }
        
        if (poolTokenAmount != uint256(0)) {
            IERC20(stakedTokenContractAddress).safeTransfer(
                _msgSender(),
                poolTokenAmount
            );
        }
        
        emit unStaked(_msgSender(), poolTokenAmount, boostTokenAmount);
    }

    function claimReward() public updateStakingReward(_msgSender()) {
        uint256 reward = stakedBalances[_msgSender()].rewards;
        require(reward > 0, "Stake: must have rewards to claim.");
        stakedBalances[_msgSender()].rewards = 0;
        TokenMinter(stakeRewardTokenContractAddress).mint(
            _msgSender(),
            reward
        );
        emit Rewards(_msgSender(), reward);
    }
}
