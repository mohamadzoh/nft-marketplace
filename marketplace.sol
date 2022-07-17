// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//
interface IERC is IERC721 {
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

contract NftTrader is Ownable {
    constructor() {
        _fee = 100;
        _auctionfee = 10;
    }

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    mapping(address => mapping(uint32 => _listing)) private _listings;
    mapping(address => mapping(uint32 => _auction)) private _auctions;
    mapping(address => mapping(address => mapping(address => mapping(uint32 => _offer)))) private _offers;
    uint16 _fee;
    uint16 _auctionfee;
    //structure of data for the item listing
    struct _listing {
        uint256 price;
        address seller;
        bool ongoing;
    }
    //structure of data for the auction
    struct _auction {
        uint32 bidCount;
        uint256 nftHighestBid;
        uint256 minBid;
        address nftHighestBidder;
        address seller;
        uint128 startDate;
        uint128 endDate;
        bool ongoing;
    }
    struct _offer {
        uint256 offer;
        bool ongoing;
    }

    //item selling fee on base of 1000 mean 100=10% and 1=0.01%
    function sellFee() external view returns (uint16) {
        return _fee;
    }

    //item auction fee on base of 1000 mean 100=10% and 1=0.01%

    function auctionFee() external view returns (uint16) {
        return _auctionfee;
    }

    // change item selling fee

    function setSellFee(uint16 fee) external onlyOwner returns (bool) {
        _fee = fee;
        return true;
    }

    // change item auction fee
    function setAuctionFee(uint16 fee) external onlyOwner returns (bool) {
        _auctionfee = fee;
        return true;
    }

    // the list of event ( for tracking  smart contract  change in real time in the backend)
    event itemSold(
        address indexed contractAddress,
        uint32 tokenId,
        uint256 price,
        address buyer,
        address seller
    );
    event FraudDetected(
        address indexed contractAddress,
        uint32 tokenId,
        address indexed fraud,
        uint32 fraudType
    );
    event listItem(
        address seller,
        address indexed contractAddress,
        uint32 tokenId,
        uint256 price
    );
    event cancelListItem(address contractAddress, uint256 tokenId);
    event startAuction(
        address seller,
        address indexed contractAddress,
        uint32 tokenId,
        uint256 price,
        uint256 minBid,
        uint256 startDate,
        uint256 endDate
    );
    event auctionSettled(
        address indexed contractAddress,
        uint32 tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );
    event auctionSettledNoBidder(
        address indexed contractAddress,
        uint32 tokenId,
        address seller
    );
    event cancelAuction(
        address indexed contractAddress,
        uint32 tokenId,
        address seller
    );
    event newBid(
        address indexed contractAddress,
        uint32 indexed tokenId,
        address bidder,
        uint256 price
    );
    event newOffer(
        address indexed contractAddress,
        uint32 indexed tokenId,
        address offerMaker,
        address recipient,
        uint256 price
    );
    event offerAccepted(
        address indexed contractAddress,
        uint32 indexed tokenId,
        address offerMaker,
        address recipient,
        uint256 price
    );
    event offerCanceled(
        address indexed contractAddress,
        uint32 indexed tokenId,
        address offerMaker,
        address recipient,
        uint8 by
    );

    // by=1 mean offer maker canceled offer offer =2 mean offer reciver canceled offer

    //add item for listing
    function addListing(
        uint256 price,
        address contractAddress,
        uint32 tokenId
    ) public {
        IERC token = IERC(contractAddress);
        require(
            token.ownerOf(tokenId) == msg.sender,
            "caller must own given token"
        );
        require(
            token.isApprovedForAll(msg.sender, address(this)),
            "contract must be approved"
        );
        require(
            _listings[contractAddress][tokenId].ongoing != true,
            "Item is already listed"
        );
        _listings[contractAddress][tokenId] = _listing(price, msg.sender, true);
        emit listItem(msg.sender, contractAddress, tokenId, price);
    }

    //cancel listing of item
    function cancelListing(address contractAddress, uint32 tokenId) public {
        IERC token = IERC(contractAddress);
        require(
            token.ownerOf(tokenId) == msg.sender,
            "caller must own given token"
        );
        require(
            _listings[contractAddress][tokenId].ongoing == true,
            "item listing already over"
        );
        _listings[contractAddress][tokenId].ongoing = false;
        emit cancelListItem(contractAddress, tokenId);
    }

    //this function is used for purchase the nft listed at fixed price in marketplace
    function purchase(address contractAddress, uint32 tokenId) public payable {
        _listing storage listedNft = _listings[contractAddress][tokenId];
        require(msg.value >= listedNft.price, "insifficient funds sent");
        require(listedNft.ongoing == true, "nft not listed for sale");
        require(listedNft.seller != msg.sender, "nft seller cant buy it");
        IERC token = IERC(contractAddress);
        listedNft.ongoing = false;
        if (token.ownerOf(tokenId) != listedNft.seller) {
            emit FraudDetected(contractAddress, tokenId, listedNft.seller, 1);
            payable(msg.sender).transfer(msg.value);
        } else {
            uint256 pay = (msg.value * (1000 - _fee)) / 1000;
            if (token.supportsInterface(_INTERFACE_ID_ERC2981)) {
                (address royal, uint256 amount) = token.royaltyInfo(
                    tokenId,
                    pay
                );
                if (amount > 0) {
                    payable(royal).transfer(amount);
                    payable(listedNft.seller).transfer(pay - amount);
                } else {
                    payable(listedNft.seller).transfer(pay);
                }
            } else {
                payable(listedNft.seller).transfer(pay);
            }
            token.safeTransferFrom(listedNft.seller, msg.sender, tokenId);
            payable(owner()).transfer(msg.value - pay);
            emit itemSold(
                contractAddress,
                tokenId,
                listedNft.price,
                msg.sender,
                listedNft.seller
            );
        }
    }

    function listingData(address contractAddress, uint32 tokenId)
        external
        view
        returns (
            uint256 price,
            address seller,
            bool ongoing
        )
    {
        _listing memory listedNft = _listings[contractAddress][tokenId];
        return (listedNft.price, listedNft.seller, listedNft.ongoing);
    }

    //create auction for the item contract addresss is collection address)
    function createAuction(
        address contractAddress,
        uint32 tokenId,
        uint256 minPrice,
        uint256 minBid,
        uint128 startDate,
        uint128 endDate
    ) public {
        require(
            minPrice >= 10000 && minPrice >= minBid,
            "Price is so lower than 1000 or min bid smaller than the price"
        );
        require(startDate < endDate, "start date smaller than end date");
        IERC token = IERC(contractAddress);
        require(
            token.ownerOf(tokenId) == msg.sender,
            "caller must own given token"
        );
        require(
            token.isApprovedForAll(msg.sender, address(this)),
            "contract must be approved"
        );
        require(
            _auctions[contractAddress][tokenId].ongoing != true,
            "This item is already in Auction"
        );
        _auctions[contractAddress][tokenId] = _auction(
            0,
            minPrice - minBid,
            minBid,
            msg.sender,
            msg.sender,
            startDate,
            endDate,
            true
        );
        emit startAuction(
            msg.sender,
            contractAddress,
            tokenId,
            minPrice,
            minBid,
            startDate,
            endDate
        );
    }

    //bidding in auction
    function bid(address contractAddress, uint32 tokenId) public payable {
        _auction storage auction = _auctions[contractAddress][tokenId];
        require(auction.startDate < block.timestamp, "Auction didn't start yet");
        require(
            auction.endDate > block.timestamp && auction.ongoing == true,
            "Auction already ended"
        );
        require(
            msg.value >= auction.nftHighestBid + auction.minBid,
            "insifficient funds sent"
        );
        require(auction.seller != msg.sender, "owner of nft can't bid");
        if (auction.bidCount++ > 0)
            payable(auction.nftHighestBidder).transfer(auction.nftHighestBid);
        auction.nftHighestBid = msg.value;
        auction.nftHighestBidder = msg.sender;
        emit newBid(contractAddress, tokenId, msg.sender, msg.value);
    }

    //retieve all the auction Data from the smart contract
    function auctionData(address contractAddress, uint32 tokenId)
        external
        view
        returns (
            uint32 bidcount,
            uint256 nftHighestBid,
            uint256 minBid,
            address nftHighestBidder,
            address seller,
            uint128 startDate,
            uint128 endDate,
            bool ongoing
        )
    {
        _auction memory auction = _auctions[contractAddress][tokenId];
        return (
            auction.bidCount,
            auction.nftHighestBid,
            auction.minBid,
            auction.nftHighestBidder,
            auction.seller,
            auction.startDate,
            auction.endDate,
            auction.ongoing
        );
    }

    //used for settling the contract can be called  by the seller or the winner of auction,used for sending nft and ether for each side;
    function settleAuction(address contractAddress, uint32 tokenId)
        public
        payable
    {
        _auction storage auction = _auctions[contractAddress][tokenId];
        require(auction.ongoing == true, "auction end");
        require(auction.endDate < block.timestamp, "Auction not ended yet");
        require(
            auction.seller == msg.sender ||
                msg.sender == auction.nftHighestBidder,
            "not allowed to do this"
        );
        auction.ongoing = false;
        if (auction.nftHighestBidder != auction.seller) {
            IERC token = IERC(contractAddress);
            if (token.ownerOf(tokenId) != auction.seller) {
                emit FraudDetected(contractAddress, tokenId, auction.seller, 2);
                payable(auction.nftHighestBidder).transfer(
                    auction.nftHighestBid
                );
            } else {
                uint256 pay = (auction.nftHighestBid * (1000 - _auctionfee)) /
                    1000;
                if (token.supportsInterface(_INTERFACE_ID_ERC2981)) {
                    (address royal, uint256 amount) = token.royaltyInfo(
                        tokenId,
                        pay
                    );
                    if (amount > 0) {
                        payable(royal).transfer(amount);
                        payable(auction.seller).transfer(pay - amount);
                    } else {
                        payable(auction.seller).transfer(pay);
                    }
                } else {
                    payable(auction.seller).transfer(pay);
                }
                payable(owner()).transfer(auction.nftHighestBid - pay);
                token.safeTransferFrom(
                    auction.seller,
                    auction.nftHighestBidder,
                    tokenId
                );
                emit auctionSettled(
                    contractAddress,
                    tokenId,
                    auction.nftHighestBidder,
                    auction.seller,
                    auction.nftHighestBid
                );
            }
        } else {
            emit auctionSettledNoBidder(
                contractAddress,
                tokenId,
                auction.seller
            );
        }
    }

    function cancelingAuction(address contractAddress, uint32 tokenId)
        public
        payable
    {
        _auction storage auction = _auctions[contractAddress][tokenId];
        require(auction.ongoing == true, "No Auction");
        require(msg.sender == auction.seller, "not the auction Maker");
        require(auction.endDate > block.timestamp, "Auction already ended");
        if (auction.bidCount > 0) {
            payable(auction.nftHighestBidder).transfer(auction.nftHighestBid);
        }
        auction.ongoing = false;
        emit cancelAuction(contractAddress, tokenId, msg.sender);
    }

    function createOffer(
        address recipient,
        address contractAddress,
        uint32 tokenId
    ) public payable {
        IERC token = IERC(contractAddress);
        require(
            token.ownerOf(tokenId) == recipient,
            "Offer recipient not the nft Owner"
        );
        require(msg.value > 10000, "please send more fund");
        require(
            _offers[msg.sender][recipient][contractAddress][tokenId].ongoing !=
                true,
            "please Cancel active offer before continue"
        );
        _offers[msg.sender][recipient][contractAddress][tokenId] = _offer(
            msg.value,
            true
        );
        emit newOffer(
            contractAddress,
            tokenId,
            msg.sender,
            recipient,
            msg.value
        );
    }

    function cancelOffer(
        address offerMaker,
        address recipient,
        address contractAddress,
        uint32 tokenId
    ) public payable {
        _offer storage offer=_offers[offerMaker][recipient][contractAddress][tokenId];
        require(
            msg.sender == offerMaker || msg.sender == recipient,
            "dont have permission for cancel this offer"
        );
        require(
            offer.ongoing ==
                true,
            "Offer not valid"
        );
        offer
            .ongoing = false;
        if (msg.sender == offerMaker) {
            emit offerCanceled(
                contractAddress,
                tokenId,
                msg.sender,
                recipient,
                1
            );
        } else {
            emit offerCanceled(
                contractAddress,
                tokenId,
                offerMaker,
                msg.sender,
                2
            );
        }
        payable(offerMaker).transfer(
            offer.offer
        );
    }

    function acceptOffer(
        address offerMaker,
        address contractAddress,
        uint32 tokenId
    ) public payable {
        IERC token = IERC(contractAddress);
        _listing storage nftListing=_listings[contractAddress][tokenId].ongoing;
        _auction storage auction =_auctions[contractAddress][tokenId];
        require(
            _offers[offerMaker][msg.sender][contractAddress][tokenId].ongoing ==
                true,
            "Offer not valid"
        );
        require(
            token.isApprovedForAll(msg.sender, address(this)),
            "contract must be approved"
        );
        uint256 offer = _offers[offerMaker][msg.sender][contractAddress][
            tokenId
        ].offer;
        if (token.ownerOf(tokenId) != msg.sender) {
            emit FraudDetected(contractAddress, tokenId, msg.sender, 3);
            payable(offerMaker).transfer(offer);
        } else {
            if (nftListing.ongoing == true) {
                nftListing.ongoing = false;
                emit cancelListItem(contractAddress, tokenId);
            }
            if (auction.ongoing == true) {
                require(
                    auction.endDate >
                        block.timestamp,
                    "please settle the active auction you can't accept the offer"
                );
                if (auction.bidCount > 0) {
                    payable(
                        auction.nftHighestBidder
                    ).transfer(
                            auction.nftHighestBid
                        );
                }
                auction.ongoing = false;
                emit cancelAuction(contractAddress, tokenId, msg.sender);
            }
            uint256 pay = (offer * (1000 - _fee)) / 1000;
            if (token.supportsInterface(_INTERFACE_ID_ERC2981)) {
                (address royal, uint256 amount) = token.royaltyInfo(
                    tokenId,
                    pay
                );
                if (amount > 0) {
                    payable(royal).transfer(amount);
                    payable(msg.sender).transfer(pay - amount);
                } else {
                    payable(msg.sender).transfer(pay);
                }
            } else {
                payable(msg.sender).transfer(pay);
            }
            token.safeTransferFrom(msg.sender, offerMaker, tokenId);
            payable(owner()).transfer(offer - pay);
            emit offerAccepted(
                contractAddress,
                tokenId,
                offerMaker,
                msg.sender,
                offer
            );
            delete _offers[offerMaker][msg.sender][contractAddress][tokenId];
        }
    }
}
