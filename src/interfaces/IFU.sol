// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1046} from "./IERC1046.sol";
import {IERC2612} from "./IERC2612.sol";
import {IERC5267} from "./IERC5267.sol";
import {IERC5805} from "./IERC5805.sol";
import {IERC6093} from "./IERC6093.sol";
import {IERC7674} from "./IERC7674.sol";

interface IFU is IERC1046, IERC2612, IERC5267, IERC5805, IERC6093, IERC7674 {
    /// @dev Emitted only once, on deployment, indicating the git commit hash from which this
    /// contract was built.
    event GitCommit(bytes20 indexed gitCommit);

    /// @notice Returns the UniswapV2 pair address where this token is paired with WETH. 
    /// @notice The UniswapV2 pair address is the only address that does not participate in the
    /// "reflection".
    function pair() external view returns (address uniV2Pair);

    /// @notice Returns the URI of the image/icon representing this token.
    function image() external view returns (string memory URI);

    /// @notice Returns the tax rate (in basis points) applied to *ALL* transfers. 
    /// @notice This is not a constant value.
    function tax() external view returns (uint256 basisPoints);

    /// @notice Returns the maximum possible balance of the account. 
    /// @notice Any action that would result in the account going over this balance causes the
    /// excess tokens to be implicitly `deliver()`'d. 
    /// @notice This is not a constant value.
    function whaleLimit(address account) external view returns (uint256 maxBalance);

    /// @notice Returns the sum of the current voting weight of all accounts.
    function getTotalVotes() external view returns (uint256);

    /// @notice Returns the sum of the historical voting weight of all accounts. 
    /// @notice If this function does not revert, this is a constant value.
    function getPastTotalVotes(uint256 timepoint) external view returns (uint256);

    /// @notice Destroys `amount` tokens from the caller's account. 
    /// @notice These tokens are removed from circulation, reducing `totalSupply()`.
    function burn(uint256 amount) external returns (bool);

    /// @notice Destroys `amount` tokens from `from` using the allowance mechanism. `amount` is
    /// then deducted from the caller's allowance. 
    /// @notice These tokens are removed from circulation, reducing `totalSupply()`.
    function burnFrom(address from, uint256 amount) external returns (bool);

    /// @notice Deducts `amount` tokens from the caller's account. 
    /// @notice These tokens are "reflected" or minted back to other tokens holders, proportionately. 
    /// @notice `totalSupply()` remains unchanged.
    function deliver(uint256 amount) external returns (bool);

    /// @notice Deducts `amount` tokens from `from` using the allowance mechanism. `amount` is then
    /// deducted from the caller's allowance. 
    /// @notice These tokens are "reflected" or minted back to other tokens holders, proportionately. 
    /// @notice `totalSupply()` remains unchanged.
    function deliverFrom(address from, uint256 amount) external returns (bool);
}
