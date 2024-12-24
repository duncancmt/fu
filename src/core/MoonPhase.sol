// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "../types/BasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

library MoonPhase {
    using UnsafeMath for int256;
    
    uint256 private constant _EPOCH = 1735597605; // 2024-12-30T22:26:45Z, the last new moon of 2024
    uint256 private constant _SYNODIC_MONTH_NANOSEC = 2551442876907840;

    function _tern(bool c, uint256 x, uint256 y) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := xor(x, mul(xor(x, y), c))
        }
    }

    function _tern(bool c, int256 x, int256 y) private pure returns (int256 r) {
        assembly ("memory-safe") {
            r := xor(x, mul(xor(x, y), c))
        }
    }

    function moonPhase(uint256 timestamp) internal pure returns (BasisPoints) {
        // This is performed outside the `unchecked` block because we want underflow checking
        uint256 reEpoch = timestamp - _EPOCH;
        unchecked {
            // `monthElapsed` represents the position of the current moment within the lunar
            // month. It's a linear value, even though the illumination of the moon is nonlinear in
            // time.
            uint256 monthElapsed = reEpoch * 1 ether / _SYNODIC_MONTH_NANOSEC % 1 gwei;

            // Now that we have the sawtooth function `monthElapsed` that ranges from 0 at the new
            // moon to 0.5 at the full moon to 1 at the next new moon, we want to convert that into
            // a smooth function representing the illuminated portion of the moon's face. We must
            // take the cosine of `monthElapsed`.

            // For convenience, rather than represent the input to `cos` in radians, we represent it
            // in turns (with a full circle represented by 1 instead of 2π). We first reduce the
            // range of `x` from 0 to 1 to 0 to 0.25 and reflect it so that we can compute
            // `sign*sin(x)` instead.
            uint256 x;
            {
                uint256 thresh = _tern(monthElapsed < 0.5 gwei, uint256(0.75 gwei), 0.25 gwei);
                x = _tern(monthElapsed < thresh, monthElapsed - thresh, thresh - monthElapsed);
            }
            int256 sign = _tern(monthElapsed - 0.25 gwei < 0.5 gwei, int256(1), -1);

            // Now we approximate `sin(x)` via a (4, 3)-term monic-numerator rational
            // polynomial. This technique was popularized by Remco Bloemen
            // (https://2π.com/22/approximation/). We use an intermediate basis of 2**64 instead of
            // 10**9 for this computation to give enough extra precision to avoid significant
            // rounding error in the coefficients but not so much that we have to perform wasteful
            // right shifts between each coefficient. We use Horner's rule to evaluate each
            // polynomial because Knuth's and Winograd's algorithms give worse rounding error. This
            // relatively small rational polynomial is only accurate to ~1e-5, but that is more than
            // sufficient for our purposes.
            x *= 18446744073;
            
            int256 p = int256(x);
            p += 1525700193226203185;
            p *= int256(x);
            p += -93284552137022849597343993509195607076;
            p *= int256(x);
            p += 2500426605410053227278254715722618320500226436344531;
            p *= sign;

            int256 q = -2132527596694872609;
            q *= int256(x);
            q += 4216729355816757570957775670381316919;
            q *= int256(x);
            q += -273763917958281728795650899975241599620736138002175265032;

            // Now `p/q` if computed exactly represents `cos(x)`. What we actually want, though is
            // `(1 + cos(x)) / 4`.
            return BasisPoints.wrap(uint256(((p + q) * 2500).unsafeDiv(q)) + 1);
        }
    }
}
