// ERCX: Inspired by all the great work out there from ERC20, 404, 721, 721a, 721Psi, 1155, 1155Delta

// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LibBitmap} from "https://github.com/Vectorized/solady/blob/main/src/utils/LibBitmap.sol";
import {LibBit} from "https://github.com/vectorized/solady/blob/main/src/utils/LibBit.sol"; 


interface IERCX {
    /**
     * The caller must own the token or be an approved operator.
     */
    error ApprovalCallerNotOwnerNorApproved();

    /**
     * Cannot query the balance for the zero address.
     */
    error BalanceQueryForZeroAddress();

    /**
     * Cannot mint to the zero address.
     */
    error MintToZeroAddress();

    /**
     * The quantity of tokens minted must be more than zero.
     */
    error MintZeroQuantity();

    /**
     * Cannot burn from the zero address.
     */
    error BurnFromZeroAddress();

    /**
     * Cannot burn from the address that doesn't owne the token.
     */
    error BurnFromNonOnwerAddress();

    /**
     * The caller must own the token or be an approved operator.
     */
    error TransferCallerNotOwnerNorApproved();

    /**
     * The token must be owned by `from` or the `amount` is not 1.
     */
    error TransferFromIncorrectOwnerOrInvalidAmount();

    /**
     * Cannot safely transfer to a contract that does not implement the
     * ERC1155Receiver interface.
     */
    error TransferToNonERC1155ReceiverImplementer();
    error TransferToNonERC721ReceiverImplementer();

    /**
     * Cannot transfer to the zero address.
     */
    error TransferToZeroAddress();

    /**
     * The length of input arraies is not matching.
     */
    error InputLengthMistmatch();

    function isOwnerOf(address account, uint256 id) external view returns(bool);
}

abstract contract ERC721Receiver is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721Receiver.onERC721Received.selector;
    }
}


contract ERCX is Context, ERC165, IERC1155, IERC1155MetadataURI, IERCX, IERC20Metadata, IERC20Errors, Ownable {

    using Address for address;
    using LibBitmap for LibBitmap.Bitmap;

    error InvalidQueryRange();

    // The mask of the lower 160 bits for addresses.
    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;
    // The `Transfer` event signature is given by:
    // `keccak256(bytes("Transfer(address,address,uint256)"))`.
    bytes32 private constant _TRANSFER_EVENT_SIGNATURE = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // Mapping from accout to owned tokens
    mapping(address => LibBitmap.Bitmap) internal _owned;
    
    // Mapping from account to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
    string private _uri;

    // The next token ID to be minted.
    uint256 private _currentIndex;

    // NFT Approval
    mapping(uint256 => address) public getApproved;

    //Token balances
    mapping(address => uint256) internal _balances;

    //Token allowances
    mapping(address account => mapping(address spender => uint256)) private _allowances;
    
    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Decimals for supply
    uint8 public immutable decimals;

    // Total ERC20 supply
    uint256 public immutable totalSupply;

    // Tokens Per NFT
    uint256 public immutable decimalFactor;
    uint256 public immutable tokensPerNFT;

    // Don't mint for these wallets
    mapping(address => bool) public whitelist;

    // Easy Launch - auto-whitelist first transfer which is probably the LP
    uint256 public easyLaunch = 1;

    /**
     * @dev See {_setURI}.
     */
    constructor(string memory uri_, string memory _name, string memory _symbol, uint8 _decimals, uint256 _totalNativeSupply, uint256 _tokensPerNFT) Ownable(msg.sender) {
        _setURI(uri_);
        _currentIndex = _startTokenId();
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        decimalFactor = 10 ** decimals;
        tokensPerNFT = _tokensPerNFT * decimalFactor;
        totalSupply = _totalNativeSupply * decimalFactor;
        whitelist[msg.sender] = true;
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /**
     * @dev Returns if 1155 events are enabled.
     * Override or change to true for 1155 flag on etherscan.
     * In 1155 mode Etherscan ignores CA reported balances and incorrectly 
     * calculates wallet balances
     */
    function erc1155Enabled() internal pure virtual returns (bool) {
        return false;
    }

    /** @notice Initialization function to set pairs / etc
     *  saving gas by avoiding mint / burn on unnecessary targets
     */
    function setWhitelist(address target, bool state) public virtual onlyOwner {
        whitelist[target] = state;
    }

    /**
     * @dev Returns the starting token ID.
     * To change the starting token ID, please override this function.
     */
    function _startTokenId() internal pure virtual returns (uint256) {
        return 1;
    }

    /**
     * @dev Returns the next token ID to be minted.
     */
    function _nextTokenId() internal view returns (uint256) {
        return _currentIndex;
    }

    /**
     * @dev Returns the total amount of tokens minted in the contract.
     */
    function _totalMinted() internal view returns (uint256) {
        return _nextTokenId() - _startTokenId();
    }

    /**
     * @dev Returns true if the account owns the `id` token.
     */
    function isOwnerOf(address account, uint256 id) public view virtual override returns(bool) {
        return _owned[account].get(id);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(IERCX).interfaceId ||
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
            interfaceId == 0x5b5e139f || // ERC165 interface ID for ERC721Metadata.
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155MetadataURI-uri}.
     *
     * This implementation returns the same URI for *all* token types. It relies
     * on the token type ID substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * Clients calling this function must replace the `\{id\}` substring with the
     * actual token type ID.
     */
    function uri(uint256) public view virtual override returns (string memory) {
        return _uri;
    }

    /**
     * @dev Returns the number of tokens owned by `owner`.
     */
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _balances[owner];
    }

    /**
     * @dev Returns the number of nfts owned by `owner`,
     * in the range [`start`, `stop`)
     * (i.e. `start <= tokenId < stop`).
     *
     * Requirements:
     *
     * - `start < stop`
     */
    function balanceOf(address owner, uint256 start, uint256 stop) public view virtual returns (uint256) {
        return _owned[owner].popCount(start, stop - start);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        if(account == address(0)) {
            revert BalanceQueryForZeroAddress();
        }
        if(_owned[account].get(id)) {
            return 1;
        } else {
            return 0;
        }   
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        if(accounts.length != ids.length) {
            revert InputLengthMistmatch();
        }

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        if(from == _msgSender() || isApprovedForAll(from, _msgSender())){
            _safeTransferFrom(from, to, id, amount, data, true);
        } else {
            revert TransferCallerNotOwnerNorApproved();
        }
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        if(!(from == _msgSender() || isApprovedForAll(from, _msgSender()))) {
            revert TransferCallerNotOwnerNorApproved();
        }
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `amount` cannot be zero.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data,
        bool check
    ) internal virtual {
        if(to == address(0)) {
            revert TransferToZeroAddress();
        }

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);

        _beforeTokenTransfer(operator, from, to, ids);

        if(amount == 1 && _owned[from].get(id)) {
            _owned[from].unset(id);
            _owned[to].set(id);
            _transfer(from, to, tokensPerNFT, false);
        } else {
            revert TransferFromIncorrectOwnerOrInvalidAmount();
        }

        uint256 toMasked;
        uint256 fromMasked;
        assembly {
            // Mask `to` to the lower 160 bits, in case the upper bits somehow aren't clean.
            toMasked := and(to, _BITMASK_ADDRESS)
            fromMasked := and(from, _BITMASK_ADDRESS)
            // Emit the `Transfer` event.
            log4(
                0, // Start of data (0, since no data).
                0, // End of data (0, since no data).
                _TRANSFER_EVENT_SIGNATURE, // Signature.
                fromMasked, // `from`.
                toMasked, // `to`.
                amount // `tokenId`.
            )
        }

        if(erc1155Enabled())
            emit TransferSingle(operator, from, to, id, amount);

        _afterTokenTransfer(operator, from, to, ids);

        if(check)
            _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        if(ids.length != amounts.length) {
            revert InputLengthMistmatch();
        }

        if(to == address(0)) {
            revert TransferToZeroAddress();
        }
        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if(amount == 1 && _owned[from].get(id)) {
                _owned[from].unset(id);
                _owned[to].set(id);
            } else {
                revert TransferFromIncorrectOwnerOrInvalidAmount();
            }
        }
        _transfer(from, to, tokensPerNFT * ids.length, false);

        uint256 toMasked;
        uint256 fromMasked;
        uint256 end = ids.length + 1;

        // Use assembly to loop and emit the `Transfer` event for gas savings.
        // The duplicated `log4` removes an extra check and reduces stack juggling.
        // The assembly, together with the surrounding Solidity code, have been
        // delicately arranged to nudge the compiler into producing optimized opcodes.
        assembly {
            // Mask `to` to the lower 160 bits, in case the upper bits somehow aren't clean.
            fromMasked := and(from, _BITMASK_ADDRESS)
            toMasked := and(to, _BITMASK_ADDRESS)
            // Emit the `Transfer` event.
            log4(
                0, // Start of data (0, since no data).
                0, // End of data (0, since no data).
                _TRANSFER_EVENT_SIGNATURE, // Signature.
                fromMasked, // `from`.
                toMasked, // `to`.
                mload(add(ids, 0x20)) // `tokenId`.
            )

            // The `iszero(eq(,))` check ensures that large values of `quantity`
            // that overflows uint256 will make the loop run out of gas.
            // The compiler will optimize the `iszero` away for performance.
            for {
                let arrayId := 2
            } iszero(eq(arrayId, end)) {
                arrayId := add(arrayId, 1)
            } {
                // Emit the `Transfer` event. Similar to above.
                log4(0, 0, _TRANSFER_EVENT_SIGNATURE, fromMasked, toMasked, mload(add(ids, mul(0x20, arrayId))))
            }
        }

        if(erc1155Enabled())
            emit TransferBatch(operator, from, to, ids, amounts);

        _afterTokenTransfer(operator, from, to, ids);

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev Sets a new URI for all token types, by relying on the token type ID
     * substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     *
     * By this mechanism, any occurrence of the `\{id\}` substring in either the
     * URI or any of the amounts in the JSON file at said URI will be replaced by
     * clients with the token type ID.
     *
     * For example, the `https://token-cdn-domain/\{id\}.json` URI would be
     * interpreted by clients as
     * `https://token-cdn-domain/000000000000000000000000000000000000000000000000000000000004cce0.json`
     * for token type ID 0x4cce0.
     *
     * See {uri}.
     *
     * Because these URIs cannot be meaningfully represented by the {URI} event,
     * this function emits no events.
     */
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    function _mint(
        address to,
        uint256 amount
    ) internal virtual {
        _mint(to, amount, "");
    }

    /**
     * @dev Creates `amount` tokens, and assigns them to `to`.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `amount` cannot be zero.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _mint(
        address to,
        uint256 amount,
        bytes memory data
    ) internal virtual {
       (uint256[] memory ids, uint256[] memory amounts) =  _mintWithoutCheck(to, amount);

        uint256 end = _currentIndex;
        _doSafeBatchTransferAcceptanceCheck(_msgSender(), address(0), to, ids, amounts, data);
        if (_currentIndex != end) revert();
    }

    function _mintWithoutCheck(
        address to,
        uint256 amount
    ) internal virtual returns(uint256[] memory ids, uint256[] memory amounts) {

        if(to == address(0)) {
            revert MintToZeroAddress();
        }
        if(amount == 0) {
            revert MintZeroQuantity();
        }

        address operator = _msgSender();

        ids = new uint256[](amount);
        amounts = new uint256[](amount);
        uint256 startTokenId = _nextTokenId();

        unchecked {
            require(type(uint256).max - amount >= startTokenId);
            for(uint256 i = 0; i < amount; i++) {
                ids[i] = startTokenId + i;
                amounts[i] = 1;
            }
        }
        
        _beforeTokenTransfer(operator, address(0), to, ids);

        _owned[to].setBatch(startTokenId, amount);
        _currentIndex += amount;

        uint256 toMasked;
        uint256 end = startTokenId + amount;

        assembly {
            toMasked := and(to, _BITMASK_ADDRESS)
            log4(
                0,
                0,
                _TRANSFER_EVENT_SIGNATURE,
                0,
                toMasked,
                startTokenId
            )

            for {
                let tokenId := add(startTokenId, 1)
            } iszero(eq(tokenId, end)) {
                tokenId := add(tokenId, 1)
            } {
                log4(0, 0, _TRANSFER_EVENT_SIGNATURE, 0, toMasked, tokenId)
            }
        }

        if(erc1155Enabled())
            emit TransferBatch(operator, address(0), to, ids, amounts);

        _afterTokenTransfer(operator, address(0), to, ids);

    }

    /**
     * @dev Destroys token of token type `id` from `from`
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have the token of token type `id`.
     */
    function _burn(
        address from,
        uint256 id
    ) internal virtual {
        if(from == address(0)){
            revert BurnFromZeroAddress();
        }

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);

        _beforeTokenTransfer(operator, from, address(0), ids);

        if(!_owned[from].get(id)) {
            revert BurnFromNonOnwerAddress();
        }

        _owned[from].unset(id);

        uint256 fromMasked;
        assembly {
            fromMasked := and(from, _BITMASK_ADDRESS)
            log4(
                0,
                0,
                _TRANSFER_EVENT_SIGNATURE,
                fromMasked,
                0,
                id
            )
        }

        if(erc1155Enabled())
            emit TransferSingle(operator, from, address(0), id, 1);

        _afterTokenTransfer(operator, from, address(0), ids);
    }

    /**
     * @dev Destroys tokens of token types in `ids` from `from`
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have the token of token types in `ids`.
     */
    function _burnBatch(
        address from,
        uint256[] memory ids
    ) internal virtual {
        if(from == address(0)){
            revert BurnFromZeroAddress();
        }

        address operator = _msgSender();

        uint256[] memory amounts = new uint256[](ids.length);

        _beforeTokenTransfer(operator, from, address(0), ids);

        unchecked {
            for(uint256 i = 0; i < ids.length; i++) {
                amounts[i] = 1;
                uint256 id = ids[i];
                if(!_owned[from].get(id)) {
                    revert BurnFromNonOnwerAddress();
                }
                _owned[from].unset(id);
            }
        }

        uint256 fromMasked;
        uint256 end = ids.length + 1;

        assembly {
            fromMasked := and(from, _BITMASK_ADDRESS)
            log4(
                0,
                0,
                _TRANSFER_EVENT_SIGNATURE,
                fromMasked,
                0,
                mload(add(ids, 0x20))
            )

            for {
                let arrayId := 2
            } iszero(eq(arrayId, end)) {
                arrayId := add(arrayId, 1)
            } {
                log4(0, 0, _TRANSFER_EVENT_SIGNATURE, fromMasked, 0, mload(add(ids, mul(0x20, arrayId))))
            }
        }
        
        if(erc1155Enabled())
            emit TransferBatch(operator, from, address(0), ids, amounts);

        _afterTokenTransfer(operator, from, address(0), ids);

    }

    function _burnBatch(
        address from,
        uint256 amount
    ) internal virtual {
        if(from == address(0)){
            revert BurnFromZeroAddress();
        }

        address operator = _msgSender();

        uint256 searchFrom = _nextTokenId();

        uint256[] memory amounts = new uint256[](amount);
        uint256[] memory ids = new uint256[](amount);

        unchecked {
            for(uint256 i = 0; i < amount; i++) {
                amounts[i] = 1;
                uint256 id = _owned[from].findLastSet(searchFrom);
                ids[i] = id;
                _owned[from].unset(id);
                searchFrom = id;
            }
        }

        //technically after, but we didn't have the IDs then
        _beforeTokenTransfer(operator, from, address(0), ids);

        uint256 fromMasked;
        uint256 end = amount + 1;

        assembly {
            fromMasked := and(from, _BITMASK_ADDRESS)
            log4(
                0,
                0,
                _TRANSFER_EVENT_SIGNATURE,
                fromMasked,
                0,
                mload(add(ids, 0x20))
            )

            for {
                let arrayId := 2
            } iszero(eq(arrayId, end)) {
                arrayId := add(arrayId, 1)
            } {
                log4(0, 0, _TRANSFER_EVENT_SIGNATURE, fromMasked, 0, mload(add(ids, mul(0x20, arrayId))))
            }
        }

        if(erc1155Enabled()) {
            if(amount == 1)
                emit TransferSingle(operator, from, address(0), ids[0], 1);
            else
                emit TransferBatch(operator, from, address(0), ids, amounts);
        }
        

        _afterTokenTransfer(operator, from, address(0), ids);

    }


     /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC1155: setting approval status for self");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `ids` and `amounts` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids
    ) internal virtual {}

    /**
     * @dev Hook that is called after any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `id` and `amount` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids
    ) internal virtual {}

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to != tx.origin) {
            if (IERC165(to).supportsInterface(type(IERC1155).interfaceId)) {
                try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                    if (response != IERC1155Receiver.onERC1155Received.selector) {
                        revert TransferToNonERC1155ReceiverImplementer();
                    }
                } catch Error(string memory reason) {
                    revert(reason);
                } catch {
                    revert TransferToNonERC1155ReceiverImplementer();
                }
            }
            else {
                try ERC721Receiver(to).onERC721Received(operator, from, id, data) returns (bytes4 response) {
                    if (response != ERC721Receiver.onERC721Received.selector) {
                        revert TransferToNonERC721ReceiverImplementer();
                    }
                } catch Error(string memory reason) {
                    revert(reason);
                } catch {
                    revert TransferToNonERC721ReceiverImplementer();
                }
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to != tx.origin) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert TransferToNonERC1155ReceiverImplementer();
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert TransferToNonERC1155ReceiverImplementer();
            }
        }
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory array) {
        array = new uint256[](1);
        array[0] = element;
    }

    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, value, true);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = msg.sender;
        if (value < _nextTokenId() && value > 0) {

            if(!isOwnerOf(owner, value)) {
                revert ERC20InvalidSender(owner);
            }

            getApproved[value] = spender;

            emit Approval(owner, spender, value);
        } else {
            _approve(owner, spender, value);
        }
        return true;
    }

    /// @notice Function for mixed transfers
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        if (value < _nextTokenId()) {
            if(!_owned[from].get(value)) {
                revert ERC20InvalidSpender(from);
            }    

            if (
                msg.sender != from &&
                !isApprovedForAll(from, msg.sender) &&
                msg.sender != getApproved[value]
            ) {
                revert ERC20InvalidSpender(msg.sender);
            }

            delete getApproved[value];

            _safeTransferFrom(from, to, value, 1, "", false);

        } else {
            _spendAllowance(from, msg.sender, value);
            _transfer(from, to, value, true);
        }
        return true;
    }

    function _transfer(address from, address to, uint256 value, bool mint) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value, mint);
    }

    function _update(address from, address to, uint256 value, bool mint) internal virtual {
        uint256 fromBalance = _balances[from];
        uint256 toBalance = _balances[to];
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }

        //No need to adjust balances when transfer is to self, prevent self NFT-grind
        if(from != to) {
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;

                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] = toBalance + value;
            }

            if(mint) {
                // Skip burn for certain addresses to save gas
                bool wlf = whitelist[from];
                if (!wlf) {
                    uint256 tokens_to_burn = (fromBalance / tokensPerNFT) - ((fromBalance - value) / tokensPerNFT);
                    if(tokens_to_burn > 0)
                        _burnBatch(from, tokens_to_burn);
                }

                // Skip minting for certain addresses to save gas
                if (!whitelist[to]) {
                    if(easyLaunch == 1 && wlf && from == owner()) {
                        //auto-initialize first (assumed) LP
                        whitelist[to] = true;
                        easyLaunch = 2;
                    } else {
                        uint256 tokens_to_mint = ((toBalance + value) / tokensPerNFT) - (toBalance / tokensPerNFT);
                        if(tokens_to_mint > 0)
                            _mintWithoutCheck(to, tokens_to_mint);
                    }
                }
            }
        }

        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    /**
     * @dev Returns an array of token IDs owned by `owner`,
     * in the range [`start`, `stop`)
     * (i.e. `start <= tokenId < stop`).
     *
     * This function allows for tokens to be queried if the collection
     * grows too big for a single call of {ERC1155DelataQueryable-tokensOfOwner}.
     *
     * Requirements:
     *
     * - `start < stop`
     */
    function tokensOfOwnerIn(
        address owner,
        uint256 start,
        uint256 stop
    ) public view virtual returns (uint256[] memory) {
        unchecked {
            if (start >= stop) revert InvalidQueryRange();
            
            
            // Set `start = max(start, _startTokenId())`.
            if (start < _startTokenId()) {
                start = _startTokenId();
            }
            
            // Set `stop = min(stop, stopLimit)`.
            uint256 stopLimit = _nextTokenId();
            if (stop > stopLimit) {
                stop = stopLimit;
            }

            uint256 tokenIdsLength;
            if(start < stop) {
                tokenIdsLength = balanceOf(owner, start, stop);
            } else {
                tokenIdsLength = 0;
            }
            
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);

            LibBitmap.Bitmap storage bmap = _owned[owner];
            
            for ((uint256 i, uint256 tokenIdsIdx) = (start, 0); tokenIdsIdx != tokenIdsLength; ++i) {
                if(bmap.get(i) ) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }

    /**
     * @dev Returns an array of token IDs owned by `owner`.
     *
     * This function scans the ownership mapping and is O(`totalSupply`) in complexity.
     * It is meant to be called off-chain.
     *
     * See {ERC1155DeltaQueryable-tokensOfOwnerIn} for splitting the scan into
     * multiple smaller scans if the collection is large enough to cause
     * an out-of-gas error (10K collections should be fine).
     */
    function tokensOfOwner(address owner) public view virtual returns (uint256[] memory) {
        if(_totalMinted() == 0) {
            return new uint256[](0);
        }
        return tokensOfOwnerIn(owner, _startTokenId(), _nextTokenId());
    }
}

contract ERC_X is ERCX {
    using Strings for uint256;
    string public dataURI;
    string public baseTokenURI;
    
    uint8 private constant _decimals = 18;
    uint256 private constant _totalTokens = 100000;
    uint256 private constant _tokensPerNFT = 1;
    string private constant _name = "MINER";
    string private constant _ticker = "MINER";

    // Snipe reduction tools
    uint256 public maxWallet;
    bool public transferDelay = true;
    mapping (address => uint256) private delayTimer;

    constructor() ERCX("", _name, _ticker, _decimals, _totalTokens, _tokensPerNFT) {
        dataURI = "https://i.ibb.co/";
        maxWallet = (_totalTokens * 10 ** _decimals) * 2 / 100;
    }

    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids
    ) internal override {
        if(!whitelist[to]) {
            require(_balances[to] <= maxWallet, "Transfer exceeds maximum wallet");
            if (transferDelay) {
                require(delayTimer[tx.origin] < block.number,"Only one transfer per block allowed.");
                delayTimer[tx.origin] = block.number;

                require(address(to).code.length == 0 && address(tx.origin).code.length == 0, "Contract trading restricted at launch");
            }
        }
        
        
        super._afterTokenTransfer(operator, from, to, ids);
    }

    function toggleDelay() external onlyOwner {
        transferDelay = !transferDelay;
    }

    function setMaxWallet(uint256 percent) external onlyOwner {
        maxWallet = totalSupply * percent / 100;
    }

    function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        if(id >= _nextTokenId()) revert InputLengthMistmatch();

        if (bytes(super.uri(id)).length > 0)
            return super.uri(id);
        if (bytes(baseTokenURI).length > 0)
            return string(abi.encodePacked(baseTokenURI, id.toString()));
        else {
            uint8 seed = uint8(bytes1(keccak256(abi.encodePacked(id))));

            string memory image;
            string memory color;
            string memory description;

            if (seed <= 63) {
                image = "GQRhWyF/Diamond.jpg";
                color = "Diamond";
                description = "Legendary NFTs powered by ERC1155. The Diamond NFTs are meticulously mined by industry elites and crafted with unparalleled precision, representing the zenith of luxury and digital artistry.";
            } else if (seed <= 127) {
                image = "gwdLf3f/Gold.jpg";
                color = "Gold";
                description = "Prestigious NFTs powered by ERC1155. The gold NFTs are carefully mined by expert collectors and meticulously crafted with golden excellence, symbolizing the pinnacle of digital rarity and exclusivity.";
            } else if (seed <= 191) {
                image = "FJmdrdm/Silver.jpg";
                color = "Silver";
                description = "Refined NFTs powered by ERC1155. The silver NFTs are mined by seasoned enthusiasts, adding an extra layer of sophistication to your portfolio.";
            } else if (seed <= 255) {
                image = "YLG3Jvc/Bronze.jpg";
                color = "Bronze";
                description = "Entry level NFTs powered by ERC1155. The silver NFTs are mined by aspiring collectors and meticulously crafted for accessibility.";
            }

            string memory jsonPreImage = string(abi.encodePacked('{"name": "MINER #', id.toString(), '","description":"', description, '","external_url":"https://miner.build","image":"', dataURI, image));
            return string(abi.encodePacked("data:application/json;utf8,", jsonPreImage, '","attributes":[{"trait_type":"Color","value":"', color, '"}]}'));
        }
    }

    function uri(uint256 id) public view override returns (string memory) {
        return tokenURI(id);
    }
}
