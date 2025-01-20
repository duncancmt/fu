// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC2612} from "./IERC2612.sol";
import {IERC5267} from "./IERC5267.sol";
import {IERC5805} from "./IERC5805.sol";
import {IERC6093} from "./IERC6093.sol";
import {IERC7674} from "./IERC7674.sol";

interface IFU is IERC2612, IERC5267, IERC5805, IERC6093, IERC7674 {
    event GitCommit(bytes20 indexed gitCommit);

    function pair() external view returns (address);
    function image() external view returns (string memory);
    function tax() external view returns (uint256);
    function whaleLimit(address) external view returns (uint256);

    function getTotalVotes() external view returns (uint256);
    function getPastTotalVotes(uint256) external view returns (uint256);

    function burn(uint256 amount) external returns (bool);
    function burnFrom(address from, uint256 amount) external returns (bool);
    function deliver(uint256 amount) external returns (bool);
    function deliverFrom(address from, uint256 amount) external returns (bool);
}
