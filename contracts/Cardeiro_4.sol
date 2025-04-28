// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // Basic funciotions of ERC20
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol"; // Burnable functions of ERC20
//burn(uint256 amount)
//burnFrom(address account, uint256 amount)
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For access control
//transferOwnership(address newOwner)
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
    
    // Margem de segurança para manipulação de timestamp (30 minutos)
    uint256 private constant SECURITY_MARGIN = 1800;
    
    // Event emitted when halving occurs
    event Halving(uint256 burnedAmount, uint256 timestamp);

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
    ) ERC20("Cardeiro", "CDT") Ownable(msg.sender) {
        require(_halvingRate <= 100, "Halving rate cannot exceed 100%");
        require(_halvingInterval >= SECONDS_PER_DAY, "Interval too short");
        require(_halvingInterval <= DEFAULT_HALVING_INTERVAL * 2, "Interval too long");
        
        _mint(msg.sender, initialSupply);
        treasury = _treasury;
        halvingInterval = _halvingInterval;
        halvingRate = _halvingRate;
        lastHalvingTime = block.timestamp;
    }

    // Function to check if halving is due
    function isHalvingDue() public view returns (bool) {
        return block.timestamp >= (lastHalvingTime + halvingInterval + SECURITY_MARGIN);
    }
    
    // Function to execute halving if the interval has passed
    function executeHalving() public nonReentrant {
        require(isHalvingDue(), "Halving interval not reached");
        
        uint256 treasuryBalance = balanceOf(treasury);
        uint256 burnAmount = (treasuryBalance * halvingRate) / 100;
        
        if (burnAmount > 0) {
            // Burn tokens from treasury
            _burn(treasury, burnAmount);
            
            // Update last halving time
            lastHalvingTime = block.timestamp - SECURITY_MARGIN;
            
            // Emit halving event
            emit Halving(burnAmount, block.timestamp);
        }
    }
    
    // Function to update halving parameters (only owner)
    function updateHalvingParams(uint256 _halvingInterval, uint256 _halvingRate) public onlyOwner {
        require(_halvingRate >= MIN_HALVING_RATE, "Halving rate too low");
        require(_halvingRate <= MAX_HALVING_RATE, "Halving rate too high");
        halvingInterval = _halvingInterval;
        halvingRate = _halvingRate;
    }
    
    // Function to update treasury address (only owner)
    function updateTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
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

    fallback() external payable {
        revert("Token does not accept ETH");
    }
    
    receive() external payable {
        revert("Token does not accept ETH");
    }

}