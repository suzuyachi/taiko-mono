// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.18;

import {LibUtils} from "./LibUtils.sol";
import {TaikoData} from "../../L1/TaikoData.sol";
import {LibAddress} from "../../libs/LibAddress.sol";

library LibClaiming {
    using LibAddress for address;

    event ClaimBlockBid(
        uint256 indexed id,
        address claimer,
        uint256 claimedAt,
        uint256 deposit
    );

    event BidRefunded(
        uint256 indexed id,
        address claimer,
        uint256 refundedAt,
        uint256 refund
    );

    error L1_ID();
    error L1_TOO_LATE();
    error L1_HALTED();
    error L1_ALREADY_CLAIMED();
    error L1_INVALID_CLAIM_DEPOSIT();

    // claimBlock lets a prover claim a block for only themselves to prove,
    // for a limited amount of time.
    // if the time passes and they dont submit a proof,
    // they will lose their deposit, half to the new prover, half is burnt.
    // there is a set window anyone can bid, then the winner has N time to prove it.
    // after which anyone can prove.
    function claimBlock(
        TaikoData.State storage state,
        TaikoData.Config memory config,
        uint256 blockId
    ) internal {
        if (LibUtils.isHalted(state)) revert L1_HALTED();

        if (
            state.proposedBlocks[blockId % config.maxNumBlocks].proposer ==
            address(0)
        ) {
            revert L1_ID();
        }

        // if claimauctionwindow is set, we need to make sure this bid
        // is within it.
        if (
            block.timestamp -
                state.proposedBlocks[blockId % config.maxNumBlocks].proposedAt >
            config.claimAuctionWindowInSeconds
        ) {
            revert L1_TOO_LATE();
        }

        // if user has claimed and not proven a block before, we multiply
        // requiredDeposit by the number of times they have falsely claimed.
        uint256 baseDepositRequired = config.baseClaimDepositInWei;
        if (state.timesProofNotDeliveredForClaim[tx.origin] > 0) {
            baseDepositRequired =
                config.baseClaimDepositInWei *
                (state.timesProofNotDeliveredForClaim[tx.origin] + 1);
        }

        // if user hasnt sent enough to meet their personal base deposit amount
        // we dont allow them to claim.
        if (msg.value < baseDepositRequired) {
            revert L1_INVALID_CLAIM_DEPOSIT();
        }

        TaikoData.Claim memory currentClaim = state.claims[blockId];
        // if there is an existing claimer, we need to see if msg.value sent is higher than the previous deposit.
        if (currentClaim.claimer != address(0)) {
            if (
                msg.value <
                currentClaim.deposit + config.minimumClaimBidIncreaseInWei
            ) {
                revert L1_INVALID_CLAIM_DEPOSIT();
            } else {
                // otherwise we have a new high bid, and can refund the previous claimer
                // refund the previous claimer
                currentClaim.claimer.sendEther(currentClaim.deposit);
                emit BidRefunded(
                    blockId,
                    currentClaim.claimer,
                    block.timestamp,
                    currentClaim.deposit
                );
            }
        }

        // then we can update the claim for the blockID to the new claimer
        state.claims[blockId] = TaikoData.Claim({
            claimer: tx.origin,
            claimedAt: block.timestamp,
            deposit: msg.value
        });

        emit ClaimBlockBid(blockId, tx.origin, block.timestamp, msg.value);
    }
}