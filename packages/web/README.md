# CheckIn Web

A frontend for the CheckIn smart contracts, built with native HTML, CSS, JavaScript and ethers v6. No build tools are required.

## Run locally

Serve the files over HTTP instead of opening `index.html` directly:

```bash
cd packages/web
python3 -m http.server 4173
```

Open <http://localhost:4173>.

## Initial configuration

1. Switch the wallet to the network where the contracts are deployed.
2. Open settings using the button in the upper-right corner.
3. Enter the deployed `ChallengeManager` address.
4. Use the contract detection button. The frontend discovers the linked `RewardPool`, `MockDepositToken` and `CheckInNFT` addresses, checks that contract code exists and checks the pool's manager/token bindings. Confirm the NFT manager binding separately during deployment.
5. Save the configuration. It is stored by chain ID in browser `localStorage`.

## Implemented features

- Wallet connection, network information and CHECK/NFT balances
- Browsing, searching and filtering on-chain challenges
- Creating, cancelling and joining challenges
- Automatic ERC-20 deposit allowance checks and approval requests
- Daily check-ins and permissionless finalization after expiry
- Successful participant deposit and reward NFT claims
- Cancellation refunds
- Author allocation and winner bonus claims
- Test CHECK faucet claims
- Challenge names and descriptions from IPFS/HTTPS metadata

## Hosting

All files in this directory are static. Deploy `packages/web` as the site root to GitHub Pages, Cloudflare Pages, Netlify, Vercel or another static server. The hosted page must be able to access `https://cdn.jsdelivr.net` to load ethers v6.

## Notes

- The test token exposes a public, repeatable `claim()` faucet. Use it only locally or on test networks.
- Install MetaMask or another EIP-1193-compatible EVM browser wallet.
- A challenge day is a consecutive 24-hour period measured from the challenge start, not a local calendar day.
- The current interface displays Chinese labels. This English README describes those controls; it does not change the interface language.
- See the [root README](../../README.md) for contract setup, testing, deployment, security limitations and licensing.
