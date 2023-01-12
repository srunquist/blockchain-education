// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";   

/*****************************************************************************************************
This was an academic exercise in ERC20 token creation & management created while learning Solidity. 
It lets a customer purchase tokens representing a song request for a specific performer and at a 
later time redeem the token to perform the request. (It's hard to imagine a real world scenario where 
you would want this rather than a direct transfer of funds.)

Performers must register and set their price per song. Performers may update their price and
cash out all their funds.

Since each performer sets their own price, I'm not sure this is still an ERC20 token - seems
like something else.

Developed and tested in Remix environment.
https://github.com/srunquist/blockchain-education.git

TODO:
    Test more thoroughly
    Perhaps add a tipping function (just en empty song request)
    Perhaps limit an account to 1 request per hour
    Push to a test network, push source to etherscan
*****************************************************************************************************/

contract SongRequestToken is Context, ERC20, Ownable {
    event PerfomerRegistered(address indexed performer, uint songPrice);
    event PuchasedSRT(address indexed performer, uint tokensPurchased);
    event SongRequested(address indexed performer, address indexed fan, string song, string artist, string comment);
    event CashedOut(address indexed performer, uint tokenBalance, uint amountInWei);

    // Price in wei for 1 song request, determined by each performer.
    mapping(address => uint) public performerPricesInWei;

    constructor() ERC20("SongRequestToken", "SRT") {
        // Creator gets 10 tokens for testing
        // We use _msgSender() throughout to allow usage by a contract that sets the context to an externally-owned account.
        _mint(_msgSender(), 10 * 10 ** decimals());
    }

    // Register a new performer. A performer may adjust their song price by re-registering.
    // Note that if a performer changes their price while holding a balance, they will have a fractional
    // number of tokens afterward (which can all be withdrawn - no problem).
    function registerAsPerformer(uint songPriceInWei) public virtual {
        require(songPriceInWei > 0, "Price of 0 is not supported");
        address performer = _msgSender();
        uint oldPriceInWei = performerPricesInWei[performer];
        uint currentBalance = balanceOf(performer);
        // If caller already has a balance but hasn't previously registered as a performer ...
        //  could be a fan-turned-performer ... or an exploitation attempt (to cash out at a high price). 
        //  Just don't allow it.
        require(oldPriceInWei > 0 || currentBalance == 0, "Since you have fan SRT tokens, you must use a new account to register as a performer.");

        // If performer is re-registering to change their price, convert their existing balance to their new valuation.
        // (This prevents someone from jacking up their price and withdrawing more ETH than they were paid.)
        if (oldPriceInWei > 0 && currentBalance > 0) {
            // Order of operations in the next 2 lines looks funny but is important for preserving value of fractional tokens
            uint balanceValueInWei = (currentBalance * oldPriceInWei) / 10 ** decimals();
            uint newBalance = 10**decimals() * balanceValueInWei / songPriceInWei;
            if (newBalance < currentBalance) {
                // burn the difference
                _burn(performer, currentBalance - newBalance);
            }
            else {
                // mint the difference
                _mint(performer, newBalance - currentBalance);
            }
        }

        performerPricesInWei[performer] = songPriceInWei;
        emit PerfomerRegistered(performer, songPriceInWei);
    }

    // Purchases the most whole tokens possible with the ETH provided. The remainder is returned.
    // Received ETH is held by this contract for future withdrawal by performers.
    // There is NO function for fans to withdraw (refund).
    function purchaseSRT(address performer) public virtual payable {
        require(performerPricesInWei[_msgSender()] == 0, "Performer accounts cannot purchase fan SRT tokens.");
        require(performerPricesInWei[performer] != 0, "Unknown performer address");
        uint tokenPriceInWei = performerPricesInWei[performer];

        uint valueProvided = msg.value;
        require(valueProvided >= tokenPriceInWei, "Not enough money sent for 1 request of this performer");

        uint tokensToTransfer = valueProvided / tokenPriceInWei;
        uint remainder = valueProvided - tokensToTransfer * tokenPriceInWei;

        // Credit X tokens to the message sender (buyer).
        _mint(_msgSender(), tokensToTransfer * 10 ** decimals());
        // Send back the change
        if (remainder > 0) {
            payable(_msgSender()).transfer(remainder);
        }
        emit PuchasedSRT(performer, tokensToTransfer);
    }

    function withdrawTips() public virtual {
        address performer = _msgSender();
        require(performerPricesInWei[performer] > 0, "Only performers may withdraw");
        uint balance = balanceOf(performer);
        require(balance > 0, "Sorry, you have no tokens to cash out");

        _burn(performer, balance);

        uint valueOfBalance = balance * performerPricesInWei[performer] / 10 ** decimals();
        payable(performer).transfer(valueOfBalance);
        emit CashedOut(performer, balance, valueOfBalance);
    }

    // Spends 1 SRT from the caller's balance
    function requestSong(
        address performer, 
        string memory song,
        string memory comment
    ) public virtual { 
        requestSong(performer, song, "", comment);
    }

    function _validateRequest(address performer, address allowanceAt) private view {
        require(performerPricesInWei[performer] != 0, "Unknown performer. Invite them to register!");

        // Not thrilled with this limitation, but supporting performer-to-performer transfers would be 
        // tricky due to price differential. (There's a risk of contract ETH balance no longer matching sum of performers' token values.)
        string memory message = "Song requests ";
        message = string.concat(message, allowanceAt != address(0) ? "using an allowance " : "");
        message = string.concat(message, "from a performer account are not supported.");
        require(performerPricesInWei[allowanceAt != address(0) ? allowanceAt : _msgSender()] == 0, message);
    }

    function requestSong(
        address performer, 
        string memory song,
        string memory artist, 
        string memory comment
    ) public virtual {
        _validateRequest(performer, address(0));
        require(transfer(performer, 1 * 10**decimals()), "Token transfer failed");
        emit SongRequested(performer, _msgSender(), song, artist, comment);
    }

    // Spends 1 SRT from a balance where the caller has been granted a sufficient allowance
    function requestSongFromAllowance(
        address allowanceAt, 
        address performer, 
        string memory song, 
        string memory comment
    ) public virtual {
        requestSongFromAllowance(allowanceAt, performer, song, "", comment);
    }

    function requestSongFromAllowance(
        address allowanceAt, 
        address performer, 
        string memory song, 
        string memory artist, 
        string memory comment
    ) public virtual {
        _validateRequest(performer, allowanceAt);
        require(transferFrom(allowanceAt, performer, 1 * 10**decimals()), "Token transfer failed");
        emit SongRequested(performer, _msgSender(), song, artist, comment);
    }
}
