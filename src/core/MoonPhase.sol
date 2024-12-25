// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "../types/BasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

library MoonPhase {
    using UnsafeMath for int256;

    uint256 private constant _EPOCH = 1740721485; // 2025-02-28T00:44:45Z, the last new moon of February 2025
    // This is the AVERAGE length of the synodic month at the epoch. The duration between actual new
    // moons varies significantly over short periods of time. Over long periods of time, the average
    // length of the synodic month increases slightly.
    uint256 private constant _SYNODIC_MONTH = 29.530588907 * 10 ** 7 * 24 * 60 * 60;
    uint256 private constant _SCALE = 2 ** 64 * 10 ** 7;

    function _ternary(bool c, int256 x, int256 y) private pure returns (int256 r) {
        assembly ("memory-safe") {
            r := xor(y, mul(xor(x, y), c))
        }
    }

    function moonPhase(uint256 timestamp) internal pure returns (BasisPoints) {
        // This is performed outside the `unchecked` block because we want underflow checking
        uint256 reEpoch = timestamp - _EPOCH;
        unchecked {
            // `monthElapsed` represents the position of the current moment within the current lunar
            // month. It's a linear value, even though the illumination of the moon is nonlinear in
            // time. The basis, `2 ** 64`, is chosen so that when we compute `sin` below, we can
            // avoid some extraneous bit shifts. The author considered a higher-order polynomial
            // approximation of the length of the synodic month, but concluded that it was excessive
            // given the relatively small second and third moments (compared to "reasonable"
            // timescales) as well as the significant additional complexity in taking the integral
            // of that approximation from the epoch to the present.
            uint256 monthElapsed = (reEpoch * _SCALE / _SYNODIC_MONTH) & type(uint64).max;

            // Now that we have the sawtooth function `monthElapsed` that ranges from 0 at the new
            // moon to 0.5 at the full moon to 1 at the next new moon, we want to convert that into
            // a smooth function representing the (un)illuminated portion of the moon's face. We
            // must take the cosine of `monthElapsed`.

            // For convenience, rather than represent the input to `cos` in radians, we represent it
            // in turns (with a full circle represented by 1 instead of 2π). We first reduce the
            // range of `x` from 0 to 1 to 0 to 0.25 and reflect it so that we can compute `sign *
            // sin(x)` instead.
            int256 x;
            {
                int256 thresh = _ternary(monthElapsed < 0.5 * 2 ** 64, 0.25 * 2 ** 64, 0.75 * 2 ** 64);
                x = _ternary(monthElapsed < uint256(thresh), thresh - int256(monthElapsed), int256(monthElapsed) - thresh);
            }
            int256 sign = _ternary(monthElapsed - 0.25 * 2 ** 64 < 0.5 * 2 ** 64, -1, 1);

            // Now we approximate `sign * sin(x)` via a (4, 3)-term monic-numerator rational
            // polynomial. This technique was popularized by Remco Bloemen
            // (https://2π.com/22/approximation/). The basis `2 ** 64` was chosen to give enough
            // extra precision to avoid significant rounding error in the coefficients, but not so
            // much that we have to perform wasteful right shifts between each term. We use Horner's
            // rule to evaluate each polynomial because Knuth's and Winograd's algorithms give worse
            // rounding error. This relatively small rational polynomial is only accurate to ~1e-5,
            // but that is more than sufficient for our purposes.

            int256 p = x;
            p += 1525700193226203185; // ~0.0827
            p *= x;
            p += -93284552137022849597343993509195607076; // ~-0.274
            p *= x;
            p += 2500426605410053227278254715722618320500226436344531; // ~3.98e-7
            p *= sign;

            int256 q = -2132527596694872609; // ~-0.116
            q *= x;
            q += 4216729355816757570957775670381316919; // ~0.0124
            q *= x;
            q += -273763917958281728795650899975241599620736138002175265032; // ~-0.0436

            // Now `p/q` if computed exactly represents `cos(monthElapsed)`. What we actually want,
            // though, is `(1 + cos(monthElapsed)) / 2`. We also want to represent the output as a
            // value from 1 to 5000 inclusive; this gives rise to the awkward `2500` as well as the
            // `+ 1`. `q` has no zeroes in the domain, so we don't need to worry about
            // divide-by-zero.
            return BasisPoints.wrap(uint256(((p + q) * 2500).unsafeDiv(q)) + 1);
        }
    }
}
