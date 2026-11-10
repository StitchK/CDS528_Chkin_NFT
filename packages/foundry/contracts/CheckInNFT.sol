// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CheckInNFT
/// @notice NFT minted when a participant completes a challenge.
contract CheckInNFT {
    string public constant name = "CheckIn Reward";
    string public constant symbol = "CHECKIN";

    bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 private constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;
    bytes4 private constant ERC721_ENUMERABLE_INTERFACE_ID = 0x780e9d63;

    address public immutable owner;
    address public manager;
    string private _baseURI;

    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => address tokenOwner) private _owners;
    mapping(address tokenOwner => uint256 balance) private _balances;
    mapping(uint256 tokenId => address approvedAddress) private _tokenApprovals;
    mapping(address tokenOwner => mapping(address operator => bool approved)) private _operatorApprovals;

    mapping(uint256 tokenId => string metadataURI) private _tokenURIs;
    mapping(address participant => mapping(uint256 challengeId => uint256 tokenId)) public rewardToken;
    mapping(uint256 tokenId => uint256 challengeId) public challengeOfToken;

    uint256[] private _allTokens;
    mapping(uint256 tokenId => uint256 index) private _allTokensIndex;
    mapping(address tokenOwner => uint256[] tokenIds) private _ownedTokens;
    mapping(address tokenOwner => mapping(uint256 tokenId => uint256 index)) private _ownedTokensIndex;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed tokenOwner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed tokenOwner, address indexed operator, bool approved);
    event ManagerUpdated(address indexed previousManager, address indexed newManager);

    error NotOwner();
    error NotManager();
    error InvalidAddress();
    error InvalidReceiver();
    error TokenDoesNotExist(uint256 tokenId);
    error NotTokenOwnerOrApproved(address caller, uint256 tokenId);
    error RewardAlreadyMinted(uint256 challengeId, address participant);

    constructor(string memory initialBaseURI) {
        owner = msg.sender;
        manager = msg.sender;
        _baseURI = initialBaseURI;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /// @notice Assigns the ChallengeManager allowed to mint challenge rewards.
    function setManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert InvalidAddress();

        address previousManager = manager;
        manager = newManager;

        emit ManagerUpdated(previousManager, newManager);
    }

    /// @notice Updates the base URI used when a reward has no individual metadata URI.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseURI = newBaseURI;
    }

    /// @notice Mints one reward NFT to a participant after ChallengeManager verifies success.
    /// @dev A participant can receive at most one reward for each challenge.
    function mintReward(
        address participant,
        uint256 challengeId,
        string calldata metadataURI
    ) external onlyManager returns (uint256 tokenId) {
        if (participant == address(0)) revert InvalidAddress();
        if (rewardToken[participant][challengeId] != 0) {
            revert RewardAlreadyMinted(challengeId, participant);
        }

        tokenId = _nextTokenId++;
        rewardToken[participant][challengeId] = tokenId;
        challengeOfToken[tokenId] = challengeId;

        if (bytes(metadataURI).length != 0) {
            _tokenURIs[tokenId] = metadataURI;
        }

        _mint(participant, tokenId);
    }

    function balanceOf(address tokenOwner) public view returns (uint256) {
        if (tokenOwner == address(0)) revert InvalidAddress();
        return _balances[tokenOwner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenDoesNotExist(tokenId);
        return tokenOwner;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        ownerOf(tokenId);

        string memory metadataURI = _tokenURIs[tokenId];
        if (bytes(metadataURI).length != 0) {
            return metadataURI;
        }

        return string.concat(_baseURI, _toString(tokenId));
    }

    function totalSupply() external view returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        if (index >= _allTokens.length) revert TokenDoesNotExist(index);
        return _allTokens[index];
    }

    function tokenOfOwnerByIndex(address tokenOwner, uint256 index) public view returns (uint256) {
        if (index >= _balances[tokenOwner]) revert TokenDoesNotExist(index);
        return _ownedTokens[tokenOwner][index];
    }

    /// @notice Returns all token IDs currently owned by an address.
    function tokensOfOwner(address tokenOwner) external view returns (uint256[] memory) {
        return _ownedTokens[tokenOwner];
    }

    function approve(address approved, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert NotTokenOwnerOrApproved(msg.sender, tokenId);
        }

        _tokenApprovals[tokenId] = approved;
        emit Approval(tokenOwner, approved, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == msg.sender) revert InvalidAddress();

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address tokenOwner, address operator) public view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotTokenOwnerOrApproved(msg.sender, tokenId);
        }

        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotTokenOwnerOrApproved(msg.sender, tokenId);
        }

        _transfer(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID
            || interfaceId == ERC721_INTERFACE_ID
            || interfaceId == ERC721_METADATA_INTERFACE_ID
            || interfaceId == ERC721_ENUMERABLE_INTERFACE_ID;
    }

    function _isApprovedOrOwner(address caller, uint256 tokenId) private view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return caller == tokenOwner
            || caller == _tokenApprovals[tokenId]
            || isApprovedForAll(tokenOwner, caller);
    }

    function _mint(address participant, uint256 tokenId) private {
        _balances[participant] += 1;
        _owners[tokenId] = participant;

        _addTokenToOwnerEnumeration(participant, tokenId);
        _addTokenToAllTokensEnumeration(tokenId);

        emit Transfer(address(0), participant, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (to == address(0)) revert InvalidAddress();

        address tokenOwner = ownerOf(tokenId);
        if (tokenOwner != from) revert NotTokenOwnerOrApproved(from, tokenId);

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _addTokenToOwnerEnumeration(address tokenOwner, uint256 tokenId) private {
        _ownedTokensIndex[tokenOwner][tokenId] = _ownedTokens[tokenOwner].length;
        _ownedTokens[tokenOwner].push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address tokenOwner, uint256 tokenId) private {
        uint256 lastTokenIndex = _ownedTokens[tokenOwner].length - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenOwner][tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[tokenOwner][lastTokenIndex];
            _ownedTokens[tokenOwner][tokenIndex] = lastTokenId;
            _ownedTokensIndex[tokenOwner][lastTokenId] = tokenIndex;
        }

        _ownedTokens[tokenOwner].pop();
        delete _ownedTokensIndex[tokenOwner][tokenId];
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        if (to.code.length == 0) return;

        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 result) {
            if (result != IERC721Receiver.onERC721Received.selector) revert InvalidReceiver();
        } catch {
            revert InvalidReceiver();
        }
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // value % 10 is in [0, 9], so this uint8 conversion cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
