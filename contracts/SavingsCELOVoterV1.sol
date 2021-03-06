//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IRegistry.sol";
import "./interfaces/ILockedGold.sol";
import "./interfaces/IElection.sol";
import "./interfaces/IVoterProxy.sol";

// SavingsCELO voter contract. VoterV1 supports voting for only one group
// at a time.
contract SavingsCELOVoterV1 is Ownable {
	using SafeMath for uint256;

	IVoterProxy public _proxy;
	address public votedGroup;

	IRegistry constant _registry = IRegistry(address(0x000000000000000000000000000000000000ce10));
	ILockedGold public _lockedGold;
	IElection public _election;

	constructor (address savingsCELO) public {
		_proxy = IVoterProxy(savingsCELO);
		_lockedGold = ILockedGold(_registry.getAddressForStringOrDie("LockedGold"));
		_election = IElection(_registry.getAddressForStringOrDie("Election"));
	}

	/// Changes voted group. This call revokes all current votes for currently voted group.
	/// votedGroupIndex is the index of votedGroup in SavingsCELO votes. This is expected to be 0 since
	/// SavingsCELO is supposed to be voting only for one group.
	///
	/// lesser.../greater... parameters are needed to perform Election.revokePending and Election.revokeActive
	/// calls. See Election contract for more details.
	///
	/// NOTE: changeVotedGroup can be used to clear out all votes even if SavingsCELO is voting for multiple
	/// groups. This can be useful if SavingsCELO is in a weird voting state before VoterV1 contract is installed
	/// as the voter contract.
	function changeVotedGroup(
		address newGroup,
		uint256 votedGroupIndex,
		address lesserAfterPendingRevoke,
		address greaterAfterPendingRevoke,
		address lesserAfterActiveRevoke,
		address greaterAfterActiveRevoke) onlyOwner external {
		if (votedGroup != address(0)) {
			uint256 pendingVotes = _election.getPendingVotesForGroupByAccount(votedGroup, address(_proxy));
			uint256 activeVotes = _election.getActiveVotesForGroupByAccount(votedGroup, address(_proxy));
			if (pendingVotes > 0) {
				require(
					_proxy.proxyRevokePending(
						votedGroup, pendingVotes, lesserAfterPendingRevoke, greaterAfterPendingRevoke, votedGroupIndex),
					"revokePending for voted group failed");
			}
			if (activeVotes > 0) {
				require(
					_proxy.proxyRevokeActive(
						votedGroup, activeVotes, lesserAfterActiveRevoke, greaterAfterActiveRevoke, votedGroupIndex),
					"revokeActive for voted group failed");
			}
		}
		votedGroup = newGroup;
	}

	/// Activates any activatable votes and also casts new votes if there is new locked CELO in
	/// SavingsCELO contract. Anyone can call this method, and it is expected to be called regularly to make
	/// sure all new locked CELO is deployed to earn rewards.
	function activateAndVote(
		address lesser,
		address greater
	) external {
		require(votedGroup != address(0), "voted group is not set");
		if (_election.hasActivatablePendingVotes(address(_proxy), votedGroup)) {
			require(
				_proxy.proxyActivate(votedGroup),
				"activate for voted group failed");
		}
		uint256 toVote = _lockedGold.getAccountNonvotingLockedGold(address(_proxy));
		if (toVote > 0) {
			uint256 maxVotes = _election.getNumVotesReceivable(votedGroup);
			uint256 totalVotes = _election.getTotalVotesForGroup(votedGroup);
			if (maxVotes <= totalVotes) {
				toVote = 0;
			} else if (maxVotes - totalVotes < toVote) {
				toVote = maxVotes - totalVotes;
			}
			if (toVote > 0) {
				require(
					_proxy.proxyVote(votedGroup, toVote, lesser, greater),
					"casting votes for voted group failed");
			}
		}
	}
}
