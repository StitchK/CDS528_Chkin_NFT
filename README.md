# CDS528 Chkin NFT

Repository: <https://github.com/StitchK/CDS528_Chkin_NFT>

An on-chain deposit challenge system built with Solidity, Foundry and ethers v6. Participants deposit the CHECK test token and check in during a shared challenge window. After finalization, successful participants claim their original deposit and an NFT, with a separate claim for bonuses funded by failed deposits. The contracts hold deposits and enforce allocation rules as a DeFi mechanism demonstration for the CDS528 course.

## Features and fund allocation

- **Create:** Set the deposit, future start time, duration, required check-ins, participant limit and metadata URI.
- **Join:** Approve and deposit CHECK before the start. Each address can join a challenge only once.
- **Check in:** Record at most one check-in per challenge day. Days are consecutive 24-hour periods measured from the challenge start.
- **Finalize:** Anyone can call `finalizeChallenge` after expiry. Finalization requires a transaction; it does not run automatically.
- **Succeed:** Call `claimSuccessfulParticipant` to recover the original deposit and receive an NFT in one transaction. Claim any additional token reward separately from RewardPool.
- **Fail:** Failed deposits move to RewardPool. If anyone succeeds, approximately half is divided equally among winners, while the author receives the rest, including rounding remainders. If nobody succeeds, the author receives all failed deposits.
- **Cancel:** Only the author can cancel before the start. Participants then claim their refunds individually.

Let F be the total failed deposits in token base units and W the number of successful participants. For W > 0, each winner's bonus is `floor(floor(F / 2) / W)`, and the author's allocation is `F - bonusPerWinner * W`. An author can also participate and succeed; author and winner rewards are calculated and claimed independently.

## Architecture and repository layout

| Contract | Responsibility |
| --- | --- |
| `MockDepositToken` | ERC-20 test token CHECK with 18 decimals; each `claim()` mints 1,000 CHECK |
| `ChallengeManager` | Challenge lifecycle, deposit custody, check-ins, finalization, refunds and NFT claims |
| `RewardPool` | Receipt of failed deposits, allocation accounting, author and winner bonus claims |
| `CheckInNFT` | Reward minting, challenge association, metadata, transfers and enumeration |

```text
packages/
├── foundry/
│   ├── contracts/          # Four application contracts
│   ├── test/               # 39 unit tests
│   ├── script/Deploy.s.sol # Deploys all four contracts and binds permissions
│   ├── lib/               # Vendored subset of OpenZeppelin 5.4.0
│   ├── .env.example       # Testnet configuration example
│   └── foundry.toml       # Solidity 0.8.37 and import remappings
└── web/
    ├── index.html
    ├── styles.css
    ├── app.js             # Native JavaScript and ethers 6.15.0
    └── README.md
```

Deposits, check-in records, eligibility, rewards and NFT ownership are stored on-chain. Search, filtering, wallet interaction and metadata retrieval run in the browser. The frontend connects through the wallet's RPC provider and needs no separate application backend.

## 1. Prerequisites and installation

Install Git, Foundry (`forge`, `cast`, `anvil`), Python 3 for the static HTTP server, and an EIP-1193 browser wallet such as MetaMask. The frontend needs no Node.js, npm or build step. On Windows, use WSL for the Bash commands below.

Follow the [official Foundry installation instructions](https://getfoundry.sh/introduction/installation/). A common installation method on macOS/Linux is:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Reopen the terminal or reload your shell configuration as instructed by the installer, then run:

```bash
foundryup
forge --version
cast --version
anvil --version
git --version
python3 --version
```

Clone the repository and enter the contracts package:

```bash
git clone https://github.com/StitchK/CDS528_Chkin_NFT.git
cd CDS528_Chkin_NFT/packages/foundry
```

The required OpenZeppelin sources are included in `lib/`; do not run `forge install` again. The first build downloads Solidity 0.8.37 as configured in `foundry.toml` and requires internet access. The frontend also needs access to jsDelivr to load ethers. If Google Fonts is unavailable, fallback fonts are used.

## 2. Build and test

Run these commands from `packages/foundry`:

```bash
forge build --optimize --optimizer-runs 200
forge test --optimize --optimizer-runs 200
forge test --optimize --optimizer-runs 200 -vvv
```

Optional gas report:

```bash
forge test --optimize --optimizer-runs 200 --gas-report
```

On 14 November 2026, using Foundry 1.8.5 and Solidity 0.8.37: **4 test suites, 39 passed, 0 failed, 0 skipped**.

The deployment script was also checked on a temporary Anvil chain on the same date. All four deployment transactions and both permission-binding transactions succeeded. The token address, both manager bindings and ownership were read back and checked. This local check is not a public testnet deployment.

| Test suite | Tests | Coverage areas |
| --- | ---: | --- |
| ChallengeManagerTest | 15 | Parameters, enrollment, time windows, check-ins, finalization, cancellation, refunds and repeated operations |
| RewardPoolTest | 16 | Equal allocation and remainders, no winners, zero amounts, permissions, funding, repeated settlement and claims |
| CheckInNFTTest | 5 | Minting authority, unique rewards, metadata, transfers and enumeration |
| MockDepositTokenTest | 3 | Faucet claims, transfers and infinite allowances |

Passing tests do not establish the absence of vulnerabilities. `forge build` still reports lint diagnostics concerning timestamps, casts, reentrancy/events and rounding that require review in context. Slither 0.11.6 was run on 16 November 2026: 7 findings (one medium strict-equality warning and six low timestamp warnings), with no high findings. These concern the duplicate-day guard and challenge timing rules; see security/review-2026-11-16.md for triage. This is not a professional audit.

## 3. Local deployment

Start Anvil in one terminal and keep it running:

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337
```

In another terminal, enter `packages/foundry` and deploy using Anvil's first default unlocked development account:

```bash
export LOCAL_RPC_URL=http://127.0.0.1:8545
export LOCAL_DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export NFT_BASE_URI=https://example.com/checkin/

forge script script/Deploy.s.sol:Deploy --optimize --optimizer-runs 200 \
  --rpc-url "$LOCAL_RPC_URL" \
  --sender "$LOCAL_DEPLOYER" --unlocked --broadcast
```

The `example.com` URI is a placeholder without actual NFT metadata. Replace it with your hosted metadata base URL for a metadata demonstration. The script deploys Token → RewardPool → NFT → ChallengeManager, then calls `setChallengeManager` and `setManager` from the deployment account. The script reads `NFT_BASE_URI` from the environment and returns `depositToken`, `rewardPool`, `checkInNFT` and `challengeManager`, in that order. Its entry point is now `run()`; omit the old `--sig run(string)` argument.

Transaction records are saved to `broadcast/Deploy.s.sol/31337/run-latest.json`; this generated directory is ignored by Git. Every script run deploys a new set of contracts. Restarting Anvil without persistence clears its state, so redeploy and update the frontend configuration. Use `--unlocked` only with local Anvil.

## 4. Sepolia deployment and source verification

Use a dedicated testnet wallet and obtain Sepolia test ETH, a Sepolia RPC URL and an Etherscan API key. CHECK cannot pay gas fees or replace test ETH.

Create a local environment file in `packages/foundry`:

```bash
cp .env.example .env
```

Fill in `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY`, `DEPLOYER_ADDRESS` and `NFT_BASE_URI`. The `.env` file is ignored by Git. Do not put a private key in this file, the README or the repository. Import the test wallet into an encrypted keystore; this command prompts for the private key and encryption password:

```bash
cast wallet import checkin-deployer --interactive
```

Load your completed `.env`, confirm Sepolia's chain ID is `11155111`, and check that the deployment account has test ETH:

```bash
set -a
source .env
set +a
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"
cast balance "$DEPLOYER_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL"
```

Simulate first, then broadcast. `DEPLOYER_ADDRESS` must match the public address of the `checkin-deployer` keystore:

```bash
forge script script/Deploy.s.sol:Deploy --optimize --optimizer-runs 200 \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" --account checkin-deployer

forge script script/Deploy.s.sol:Deploy --optimize --optimizer-runs 200 \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" --account checkin-deployer \
  --broadcast --verify
```

The second command deploys and submits source verification to Etherscan, reading the API key from the environment. Deployment and verification are separate steps. If transactions succeed but verification fails, verify the existing addresses using the commands below rather than deploying again. If broadcasting is interrupted, inspect `broadcast/Deploy.s.sol/11155111/run-latest.json` and on-chain transaction status before following Foundry's `--resume` procedure to avoid duplicate deployments.

Set the returned addresses and check the bindings:

```bash
export TOKEN_ADDRESS=0xYourTokenAddress
export POOL_ADDRESS=0xYourPoolAddress
export NFT_ADDRESS=0xYourNFTAddress
export MANAGER_ADDRESS=0xYourManagerAddress

cast call "$POOL_ADDRESS" 'challengeManager()(address)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$NFT_ADDRESS" 'manager()(address)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$MANAGER_ADDRESS" 'depositToken()(address)' --rpc-url "$SEPOLIA_RPC_URL"
```

The first two calls should return `MANAGER_ADDRESS`; the third should return `TOKEN_ADDRESS`. Replace all `0xYour...` placeholders before running these commands. To verify the four existing contracts individually:

```bash
FOUNDRY_OPTIMIZER=false forge verify-contract "$TOKEN_ADDRESS" contracts/MockDepositToken.sol:MockDepositToken \
  --chain sepolia --watch

FOUNDRY_OPTIMIZER=false forge verify-contract "$POOL_ADDRESS" contracts/RewardPool.sol:RewardPool \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$TOKEN_ADDRESS")" \
  --chain sepolia --watch

forge verify-contract "$NFT_ADDRESS" contracts/CheckInNFT.sol:CheckInNFT \
  --constructor-args "$(cast abi-encode 'constructor(string)' "$NFT_BASE_URI")" \
  --chain sepolia --watch --num-of-optimizations 200

forge verify-contract "$MANAGER_ADDRESS" contracts/ChallengeManager.sol:ChallengeManager \
  --constructor-args "$(cast abi-encode 'constructor(address,address,address)' "$TOKEN_ADDRESS" "$POOL_ADDRESS" "$NFT_ADDRESS")" \
  --chain sepolia --watch --num-of-optimizations 200
```

Retain the original compiler settings and NFT constructor argument to prevent verification mismatches. After deployment, record all four actual addresses, deployment transactions and `https://sepolia.etherscan.io/address/<actual-address>#code` links in the table below. Use the same records in the report.

| Network | Contract | Address and source verification link |
| --- | --- | --- |
| Sepolia (11155111) | MockDepositToken | [`0xAeDf8c2A37AceE087204d754DB44896703D8D7F2`](https://sepolia.etherscan.io/address/0xAeDf8c2A37AceE087204d754DB44896703D8D7F2#code); Sourcify exact match |
| Sepolia (11155111) | RewardPool | [`0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453`](https://sepolia.etherscan.io/address/0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453#code); Sourcify exact match |
| Sepolia (11155111) | CheckInNFT | [`0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB`](https://sepolia.etherscan.io/address/0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB#code); Sourcify exact match |
| Sepolia (11155111) | ChallengeManager | [`0xDd265997a497Bc315136a958b6b7724dE0675Ed9`](https://sepolia.etherscan.io/address/0xDd265997a497Bc315136a958b6b7724dE0675Ed9#code); Sourcify exact match |

All four contracts are deployed on Sepolia. Six transaction receipts and the cross-contract bindings were independently checked on 16 November 2026. Deployment hashes and block numbers are recorded in [deployments/11155111.json](packages/foundry/deployments/11155111.json). All four sources are now verified with exact creation and runtime matches on Sourcify; use the source links below. Etherscan source verification is pending because Sourcify’s forwarding service hit its daily submission limit. An Etherscan address link alone is not proof of Etherscan verification. The existing deployment uses Solidity 0.8.37 with mixed settings: CHECK and RewardPool have optimization disabled; NFT and ChallengeManager have optimization enabled for 200 runs. The deployment record stores settings per contract. New deployments use optimization for all four by default. The existing NFT constructor base URI is an empty string.

Sourcify verified sources: [CHECK](https://repo.sourcify.dev/contracts/full_match/11155111/0xAeDf8c2A37AceE087204d754DB44896703D8D7F2/) · [RewardPool](https://repo.sourcify.dev/contracts/full_match/11155111/0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453/) · [CheckInNFT](https://repo.sourcify.dev/contracts/full_match/11155111/0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB/) · [ChallengeManager](https://repo.sourcify.dev/contracts/full_match/11155111/0xDd265997a497Bc315136a958b6b7724dE0675Ed9/)

## 5. Run and use the frontend

From the repository root, run:

```bash
cd packages/web
python3 serve.py
```

Open <http://127.0.0.1:4173>. The server supports direct SPA routes such as `/create`, `/dashboard`, `/my-nfts` and `/challenges/1`. Do not open `file://.../index.html` directly.

1. Switch the wallet to the deployment network. Sepolia uses chain ID `11155111`; local Anvil uses `31337` with RPC URL `http://127.0.0.1:8545`.
2. For local demonstrations, import an Anvil development account into a dedicated test wallet. Its default private keys are public and must be used only for local testing.
3. Connect the wallet. Sepolia automatically loads the deployed ChallengeManager shown above. For other instances, open settings, enter the manager address, detect and save. Discovery checks contract code, the pool token and both manager bindings. Configuration is stored by chain ID in browser localStorage.
4. Claim test CHECK, create a challenge with a future start, or join an existing challenge before it starts. The detail page separates ERC-20 approval and joining into two transactions.
5. Check in during the challenge. After expiry, finalize and separately claim the deposit/NFT, winner bonus or author allocation. For cancelled challenges, use the cancellation refund flow.

A challenge's `metadataURI` should point to publicly accessible HTTPS/IPFS JSON. It can include `name`, `description` and `image`; an HTTPS service must allow browser cross-origin requests. Replace the example URLs with actual resources:

```json
{
  "name": "Seven Day CheckIn",
  "description": "Complete the required daily on-chain check-ins.",
  "image": "https://example.com/checkin/reward.png"
}
```

Publish `packages/web` as the site root and configure SPA fallback to `index.html`. Bundled reward metadata uses relative image paths resolved against its JSON URL. When previewed locally, generated metadata URIs still point to localhost and are not publicly available: host the assets over HTTPS or IPFS before creating a publicly viewable NFT. Existing on-chain URIs cannot be rewritten by changing these files. See [packages/web/README.md](packages/web/README.md) for frontend details.

## Security, permissions and limitations

- OpenZeppelin `SafeERC20`, `ReentrancyGuard` and pull payments protect value operations. State and eligibility checks reject duplicate enrollment, claims, finalization and unauthorized actions.
- Challenges support at most 50 participants and 365 days. Finalization iterates over participants; the cap bounds this work, but gas costs still require consideration.
- RewardPool's owner can bind ChallengeManager only once, and there is no arbitrary withdrawal function. The NFT owner can change the manager and base URI, so minting and metadata retain administrative trust assumptions.
- There is no emergency pause or proxy upgrade mechanism. Direct deployment reduces configuration complexity, but a defect requires users to stop using the old deployment and move to a new instance. Old contracts cannot be patched or paused in place.
- CHECK is a repeatable test faucet token. The deposit mechanism supports ordinary ERC-20 assets without transfer fees or rebasing. Accidental direct transfers to the pool are not automatically allocated, and no dedicated recovery function exists.
- A check-in proves an on-chain interaction, not real-world activity. NFTs are transferable, so the current holder may not be the original successful participant. Multiple-address participation and author incentives remain economic limitations.
- This course project is intended for local and testnet use, not custody of real assets.

## Troubleshooting

| Issue | What to check |
| --- | --- |
| `forge` command not found | Reopen the shell and confirm Foundry's bin directory is on PATH |
| First compiler download fails | Check connectivity and the Solidity version in `foundry.toml`; retain the settings used for deployment |
| Blank page or ethers fails to load | Serve over HTTP; inspect the browser console and access to jsDelivr |
| No code at an address or contract detection fails | Check the wallet network, deployment address, whether Anvil restarted, and RewardPool's manager binding |
| Joining fails | Check CHECK balance, allowance, start time, participant cap and existing membership |
| Check-in or finalization fails | Check on-chain time; allow one check-in per challenge day and finalize only after expiry |
| Claim fails | Check eligibility, finalized/cancelled state and prior claims; a zero bonus needs no claim |
| Metadata fails to display | Check the JSON, HTTPS/CORS configuration or IPFS gateway availability |

## Sources, licenses and AI assistance

The project Solidity sources declare SPDX `MIT` licensing. The vendored OpenZeppelin subset is version 5.4.0 under the MIT license; retain its source headers and [upstream license](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/LICENSE). The frontend loads ethers 6.15.0 from a CDN under its [MIT license](https://github.com/ethers-io/ethers.js/blob/v6.15.0/LICENSE.md).

OpenAI Codex assisted with directory comparison, synchronization of the existing frontend, README and deployment-script preparation, compilation, tests and local deployment checks. It also assisted with report drafting and the English README translation. This disclosure covers the documented maintenance work; the team should add earlier AI usage and human review records to the final report.

References (APA):

- OpenZeppelin. (n.d.). *OpenZeppelin Contracts 5.x*. https://docs.openzeppelin.com/contracts/5.x/
- Foundry. (n.d.). *Foundry documentation*. https://getfoundry.sh/
- ethers. (n.d.). *ethers documentation v6*. https://docs.ethers.org/v6/
- Ethereum.org. (n.d.). *Ethereum development documentation*. https://ethereum.org/en/developers/docs/
- Solidity. (n.d.). *Solidity documentation*. https://docs.soliditylang.org/
