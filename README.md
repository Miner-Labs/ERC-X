# ERC-X

## Introduction

ERC-X is a fully optimized, experimental standard that enables the use of multiple standards in one (ERC20, ERC404, ERC721, ERC721A, ERC721Psi, ERC1155, and ERC1155Delta).

ERC-X is gas-efficient and scales to nearly any project size, with adjustable tokens per NFT amount. It also reintroduces all the standard features from ERC20s such as anti-snipe for smoother launches.

## Usage

To deploy your own ERC-X token, look at the example file provided ERCX.sol.

## Switching between ERC721 and ERC1155

In your contract, you can enable ERC1155 event tracking by overriding the erc1155Enabled() function and returning true. While the contract remains compatible with ERC1155 even when this feature is off, it will not be recognized as an ERC1155 token on Etherscan; instead, it will default to being categorized as an ERC721 token. In the given contract, this feature is activated by default.

## EasyLaunch™

With EasyLaunch, the token launch process is streamlined to just two steps: deploy and add liquidity. This simplicity contrasts with other ERC404 and DN404 versions, where you must deploy, whitelist your wallet, manually initialize the liquidity pool without adding tokens — a step not supported by the Uniswap interface — whitelist the liquidity provider, and then add liquidity. Alternatively, you might need to simulate the entire process to obtain the future liquidity provider address for whitelisting. EasyLaunch significantly simplifies the procedure, reducing it to only two straightforward steps.

```
// Easy Launch - auto-whitelist first transfer which is probably the LP
    uint256 public easyLaunch = 1;
```

## License

This software is released under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
