FU is a shitpost of a token. It was designed and implemented purely for the
amusement of its authors and its participants. It is, in a sense, blockchain
art. By holding FU, you are participating in this art project. The authors hope
that it brings you joy, because it won't bring you wealth.

While FU is ownerless, decentralized, and great pains have been taken to ensure
that it is bug-free, its authors make no guarantees about its correctness. See
[LICENSE.txt](./LICENSE.txt) for full terms.

# Goals

FU is designed to be maximally vexing for developers to integrate, while still
being technically correct.

## Features

* Unreasonably high decimals (36)
* Reflection (both tax _and_ rebase)
* Tax rate changes depending on the phase of the moon
* Randomly reverts or returns `false` to signal failure
* Randomly returns nothing or returns `true` to signal success
* `symbol` depends on the identity of the caller
* The shares-to-tokens ratio depends on the address of the holder
  * Consequently, `totalSupply` is merely an upper bound on the sum of all
    `balanceOf(...)`
* Anti-whale

## Extension standards

FU is a full-featured token, supporting the following extensions to the ERC20 standard (with metadata)

 * [ERC2612](https://eips.ethereum.org/EIPS/eip-2612) -- EIP-20 approvals via EIP-712 secp256k1 signatures
 * [ERC5267](https://eips.ethereum.org/EIPS/eip-5267) -- Retrieval of EIP-712 domain
 * [ERC5805](https://eips.ethereum.org/EIPS/eip-5805) -- Voting with delegation
 * [ERC6093](https://eips.ethereum.org/EIPS/eip-6093) -- Custom errors for commonly-used tokens
 * [ERC6372](https://eips.ethereum.org/EIPS/eip-6372) -- Contract clock
 * [ERC7674](https://eips.ethereum.org/EIPS/eip-7674) -- Temporary Approval Extension for ERC-20

## Non-standard extensions

 * `tax()(uint256)` (view)
 * `getTotalVotes()(uint256)` (view)
 * `getPastTotalVotes(uint256)(uint256)` (view)
 * `burn(uint256)(bool)`
 * `burnFrom(address,uint256)(bool)`
 * `deliver(uint256)(bool)`
 * `deliverFrom(address,uint256)(bool)`

The allowance from each account to Permit2
(0x000000000022D473030F116dDEE9F6B43aC78BA3) is always infinity
(`type(uint256).max`).

## Restrictions

FU is designed to still be strictly compliant with
[ERC20](https://eips.ethereum.org/EIPS/eip-20) as written. However, to make
things a little more interesting, I've applied some additional restrictions
beyond what ERC20 literally requires.

* Calls to `transfer` or `transferFrom` reduce the balance of the caller/`from`
  by exactly the specified amount
* Calls to `transfer` or `transferFrom` increase the balance of `to` by a value
  that lies in the range of reasonable interpretations of how it should be
  calculated
  * Lower bound: compute the tax amount exactly, round it up, then deduct it
    from the specified amount
  * Upper bound: exactly compute the specified amount minus the tax, round it up

"Normal" reflection tokens do not have these properties, and the author adopted
them primarily to demonstrate mastery of the required numerical programming
techniques.

# Testing

FU was developed using the [Foundry](https://github.com/foundry-rs/foundry)
framework with [Slither](https://github.com/crytic/slither) for static analysis
and [medusa](https://github.com/crytic/medusa) as a coverage-guided complement
to Foundry's fuzzer.

The differential fuzz tests and invariant/property tests in this repository take
quite a long time to run.

## Install some tools

[Install Foundry](https://book.getfoundry.sh/getting-started/installation)

Install analysis tools from Crytic (Trail of Bits)
```shell
python3 -m pip install --user crytic-compile
python3 -m pip install --user slither-analyzer
```

## Run some tests

```shell
forge test -vvv --fuzz-seed "$(python3 -c 'import secrets; print(secrets.randbelow(2**53))')"
./medusa fuzz # or use your system `medusa`
slither .
```
