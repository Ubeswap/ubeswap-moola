# Ubeswap Moola

[Moola](https://moola.market/) integration for Ubeswap.

Currently this consists of the `UbeswapMoolaRouter`, which allows users to perform deposits and withdrawals in the same transaction as a swap.

## Deployed Contracts

See [/deployments](deployments/) for mainnet and Alfajores contract addresses.

Contracts are verified using [Sourcify](https://sourcify.dev).

## Deployment

`<network>` is either `alfajores` or `mainnet`.

```sh
yarn hardhat deploy --network alfajores --step router
```

### Verification

Run `yarn build` and use the metadata in `build/metadata/UbeswapMoolaRouter/metadata.json` to upload to Sourcify.

## License

MIT
