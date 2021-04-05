# Ubeswap Moola

[Moola](https://moola.market/) integration for Ubeswap.

Currently this consists of the `UbeswapMoolaRouter`, which allows users to perform deposits and withdrawals in the same transaction as a swap.

## Deployed Contracts

See [/deployments](deployments/) for mainnet and Alfajores contract addresses.

## Deployment

`<network>` is either `alfajores` or `mainnet`.

```sh
yarn hardhat deploy --network alfajores --step router
```

## License

MIT
