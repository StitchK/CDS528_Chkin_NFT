# CheckIn Web

A static wallet interface built with HTML, CSS, JavaScript and ethers v6. No build step is required.

## Run

```bash
cd packages/web
python3 serve.py
```

Open <http://127.0.0.1:4173>. The server supports direct navigation to `/create`, `/dashboard`, `/my-nfts` and `/challenges/:id`. Missing assets return HTTP 404.

## Connect and configure

Use an EIP-1193 wallet on Sepolia (11155111) or local Anvil (31337). EIP-6963 discovery prefers MetaMask when available. Sepolia automatically loads manager `0xDd265997a497Bc315136a958b6b7724dE0675Ed9`. For a local deployment, enter its manager address in settings. Discovery checks contract code, the token/pool references and both manager bindings. Saved configurations are isolated by chain ID. Transaction actions request a supported network before proceeding.

## Features

- Challenge browsing, search, filters, creation and cancellation
- Detail pages with separate ERC-20 approval and enrollment actions
- Daily eligibility and next-check-in time from the contract
- Permissionless finalization, successful deposit/NFT claims and cancellation refunds
- Separate author allocation and winner bonus claims
- My Challenges, rewards and NFT gallery views
- Wallet balances and the repeatable 1,000 CHECK test faucet
- IPFS/HTTPS metadata and relative image URL resolution

The full address set, six deployment transactions and source-verification status are in [the deployment record](../foundry/deployments/11155111.json). Deployment is live; all four sources have Sourcify exact-match verification. Etherscan source verification remains pending.

## Hosting and limits

Host this directory on a static server with SPA rewrites for application routes. Allow access to jsDelivr for ethers. Localhost metadata works only on the same computer; use publicly reachable HTTPS/IPFS JSON and images for public NFTs. The supplied metadata uses relative image references.

CHECK is freely mintable and intended only for testing. A challenge day is a consecutive 24-hour period from its start, not a local calendar day. Interface labels are Chinese. See [the root README](../../README.md) for deployment, testing, security and licensing.
