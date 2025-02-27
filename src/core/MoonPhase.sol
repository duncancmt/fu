// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "../types/BasisPoints.sol";

import {Ternary} from "../lib/Ternary.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";

library MoonPhase {
    using Ternary for bool;
    using UnsafeMath for int256;

    uint256 private constant _EPOCH = 1740721485; // 2025-02-28T00:44:45Z, the last new moon of February 2025
    // This is the AVERAGE length of the synodic month at the epoch. The duration between actual new
    // moons varies significantly over short periods of time. Over long periods of time, the average
    // length of the synodic month increases slightly.
    uint256 private constant _SYNODIC_MONTH = 0x17348a775920; // 29.530588907 * 10 ** 7 * 1 days
    uint256 private constant _SCALE = 0x9896800000000000000000; // 2 ** 64 * 10 ** 7

    int256 private constant _ONE_HALF = 0x8000000000000000; // 0.5 * 2 ** 64
    int256 private constant _ONE_QUARTER = 0x4000000000000000; // 0.25 * 2 ** 64
    int256 private constant _THREE_QUARTERS = 0xc000000000000000; // 0.75 * 2 ** 64

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
            int256 monthElapsed = int256((reEpoch * _SCALE / _SYNODIC_MONTH) & type(uint64).max);

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
                int256 thresh = (monthElapsed < _ONE_HALF).ternary(_ONE_QUARTER, _THREE_QUARTERS);
                x = (monthElapsed < thresh).ternary(thresh - monthElapsed, monthElapsed - thresh);
            }
            int256 sign = (uint256(monthElapsed) - uint256(_ONE_QUARTER) < uint256(_ONE_HALF)).ternary(-1, 1); // underflow is desired

            // Now we approximate `sign * sin(x)` via a (4, 3)-term monic-numerator rational
            // polynomial. This technique was popularized by Remco Bloemen
            // (https://2π.com/22/approximation/). The basis `2 ** 64` was chosen to give enough
            // extra precision to avoid significant rounding error in the coefficients, but not so
            // much that we have to perform wasteful right shifts between each term. We use Horner's
            // rule to evaluate each polynomial because Knuth's and Winograd's algorithms give worse
            // rounding error. This relatively small rational polynomial is only accurate to ~1e-5,
            // but that is more than sufficient for our purposes.

            int256 p = x; // `p` is monic; the leading coefficient is 1
            p += 0x152c603e02fe2031; // ~0.0827
            p *= x;
            p -= 0x462df383df0568550000000000000000; // ~0.274
            p *= x;
            // The constant coefficient of `p` is so small (~3.98e-7) that it does not affect
            // accuracy if it is elided
            p *= sign;

            int256 q = -0x1d98428cf2b72221; // ~-0.116
            q *= x;
            q += 0x032c1ccefcbad6dd0000000000000000; // ~0.0124
            q *= x;
            q -= 0x0b2a3a89efcf885e00000000000000000000000000000000; // ~0.0436

            // Now `p/q` if computed exactly represents `cos(monthElapsed)`. What we actually want,
            // though, is `(1 + cos(monthElapsed)) / 2`. We also want to represent the output as a
            // value from 1 to 5000 inclusive; this gives rise to the awkward `2500` as well as the
            // `+ 1`. `q` has no zeroes in the domain, so we don't need to worry about
            // divide-by-zero.
            return BasisPoints.wrap(uint256(((p + q) * 2500).unsafeDiv(q)) + 1);
        }
    }
}
