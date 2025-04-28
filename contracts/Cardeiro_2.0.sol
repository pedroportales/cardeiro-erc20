// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Cardeiro is ERC20, ERC20Burnable, Ownable, ReentrancyGuard {

    // Treasury address to hold undistributed tokens
    address public treasury;

    // Halving interval (in seconds)
    uint256 public halvingInterval;

    // Timestamp of the last halving
    uint256 public lastHalvingTime;

    // Halving rate (in percentage, e.g., 50 means 50%)
    uint256 public halvingRate;

    uint256 private constant MIN_HALVING_RATE = 5; // 5%

    uint256 private constant MAX_HALVING_RATE = 20; // 20%

    uint256 private constant DAYS_IN_YEAR = 365;

    uint256 private constant SECONDS_PER_DAY = 86400; // 24 * 60 * 60

    uint256 private constant DEFAULT_HALVING_INTERVAL = (DAYS_IN_YEAR * 2) * SECONDS_PER_DAY; // 63072000

    // Constantes de segurança
    uint256 private constant TIMELOCK_DURATION = 1 days;
    uint256 private constant MAX_BURN_RATE = 20;

    // Variáveis para timelock
    uint256 public timelockExpiry;
    address public pendingTreasury;

    // Controle de taxa
    uint256 public lastOperationTime;
    uint256 private constant RATE_LIMIT_INTERVAL = 1 hours;

    // Event emitted when halving occurs
    event Halving(uint256 burnedAmount, uint256 timestamp);

    // Eventos adicionais para transparência
    event HalvingParamsUpdated(uint256 newInterval, uint256 newRate);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    modifier autoHalving() {
        if (isHalvingDue()) {
            executeHalving();
        }
        _;
    }

    constructor(
        uint256 initialSupply,
        address _treasury,
        uint256 _halvingInterval,
        uint256 _halvingRate
    ) ERC20("Cardeiro", "CDT2") Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_treasury != address(this), "Treasury cannot be contract");
        require(initialSupply > 0, "Supply must be positive");
        require(_halvingRate <= MAX_BURN_RATE, "Rate too high");
        require(_halvingRate <= 100, "Halving rate cannot exceed 100%");
        require(_halvingInterval >= SECONDS_PER_DAY, "Interval too short");
        require(_halvingInterval <= DEFAULT_HALVING_INTERVAL * 2, "Interval too long");

        _mint(msg.sender, initialSupply);
        treasury = _treasury;
        halvingInterval = _halvingInterval;
        halvingRate = _halvingRate;
        lastHalvingTime = block.timestamp;
            }

    // Proteção contra reentrância
    function executeHalving() public nonReentrant {
        require(_checkRateLimit(), "Rate limit exceeded");
        require(block.timestamp >= lastHalvingTime + halvingInterval, "Too early");

        uint256 treasuryBalance = balanceOf(treasury);
        uint256 burnAmount = (treasuryBalance * halvingRate) / 100;

        if (burnAmount > 0) {
            _burn(treasury, burnAmount);
            lastHalvingTime = block.timestamp;
            lastOperationTime = block.timestamp;
            emit Halving(burnAmount, block.timestamp);
        }
    }

    // Function to check if halving is due
    function isHalvingDue() public view returns (bool) {
        return block.timestamp >= lastHalvingTime + halvingInterval;
    }

    // Function to update halving parameters (only owner)
    function updateHalvingParams(uint256 _halvingInterval, uint256 _halvingRate) public onlyOwner {
        require(_halvingRate >= MIN_HALVING_RATE, "Halving rate too low");
        require(_halvingRate <= MAX_HALVING_RATE, "Halving rate too high");
        halvingInterval = _halvingInterval;
        halvingRate = _halvingRate;
        emit HalvingParamsUpdated(_halvingInterval, _halvingRate);
    }

    // Timelock para mudança de treasury
    function proposeTreasuryUpdate(address _newTreasury) public onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        require(_newTreasury != address(this), "Cannot be contract");
        pendingTreasury = _newTreasury;
        timelockExpiry = block.timestamp + TIMELOCK_DURATION;
        emit TreasuryUpdated(treasury, _newTreasury);
    }

    function confirmTreasuryUpdate() public onlyOwner {
        require(block.timestamp >= timelockExpiry, "Timelock active");
        require(pendingTreasury != address(0), "No pending update");
        address oldTreasury = treasury;
        treasury = pendingTreasury;
        pendingTreasury = address(0);
        emit TreasuryUpdated(oldTreasury, treasury);
    }

    // Function to update treasury address (only owner)
    function updateTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    // Rate limiting
    function _checkRateLimit() private view returns (bool) {
        return block.timestamp >= lastOperationTime + RATE_LIMIT_INTERVAL;
    }

    function getExpectedBurn(uint256 rate) public view returns (uint256) {
        uint256 treasuryBalance = balanceOf(treasury);
        return (treasuryBalance * rate) / 100;
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        autoHalving
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        autoHalving
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    // Fallback e receive
    fallback() external payable {
        revert("Token does not accept ETH");
    }

    receive() external payable {
        revert("Token does not accept ETH");
    }
}