# Goals

# Features

# Testing

## Install some tools

[Install Foundry](https://book.getfoundry.sh/getting-started/installation)

Install analysis tools from Crytic (Trail of Bits)
```shell
python3 -m pip install --user crytic-compile
python3 -m pip install --user slither-analyzer
```

## Run some tests

```shell
forge test -vvv --fuzz-seed "$(python3 -c 'import secrets; print(secrets.randbelow(2**64))')"
./medusa fuzz # or use your system `medusa`
slither .
```
