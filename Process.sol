pragma solidity ^0.5.0;
contract TradeProcess {
    
    address public owner;
    
    enum ProposalState {
        WAITING,
        ACCEPTED,
        REPAID
    }

    struct Proposal {
        address payable lender;
        uint tradeId;
        ProposalState state;
        uint rate;                //interest rate
        uint amount;
    }
    
    enum TradeState {
        ACCEPTING,
        LOCKED,
        SUCCESSFUL,
        FAILED
    }
    
    struct Trade {
        address borrower;
        TradeState state;
        uint dueDate;
        uint amount;
        uint proposalCount;
        uint collected;
        uint startDate;
        bytes32 mortgage;
        mapping (uint=>uint) proposal;
    }

    Trade[] public tradeList;
    Proposal[] public proposalList;

    mapping (address=>uint[]) public tradeMap;
    mapping (address=>uint[]) public lendMap;

    constructor() public{
        owner = msg.sender;
    }

     function hasActiveTrade(address borrower) public view returns(bool) {
        uint validTrades = tradeMap[borrower].length;
        if(validTrades == 0) return false;
        Trade storage obj = tradeList[tradeMap[borrower][validTrades-1]];
        if(tradeList[validTrades-1].state == TradeState.ACCEPTING) return true;
        if(tradeList[validTrades-1].state == TradeState.LOCKED) return true;
        return false;
    }

     function newTrade(uint amount, uint dueDate, bytes32 mortgage) public {
        if(hasActiveTrade(msg.sender)) return;
        uint currentDate = block.timestamp;
        tradeList.push(Trade(msg.sender, TradeState.ACCEPTING, dueDate, amount, 0, 0, currentDate, mortgage));
        tradeMap[msg.sender].push(tradeList.length-1);
    }

     function newProposal(uint tradeId, uint rate) public payable {
        if(tradeList[tradeId].borrower == address(0) || tradeList[tradeId].state != TradeState.ACCEPTING)
            return;
        proposalList.push(Proposal(msg.sender, tradeId, ProposalState.WAITING, rate, msg.value));
        lendMap[msg.sender].push(proposalList.length-1);
        tradeList[tradeId].proposalCount++;
        tradeList[tradeId].proposal[tradeList[tradeId].proposalCount-1] = proposalList.length-1;
    }

     function getActiveTradeId(address borrower) public view returns(uint) {
        uint numTrades = tradeMap[borrower].length;
        if(numTrades == 0) return (2**64 - 1);
        uint lastTradeId = tradeMap[borrower][numTrades-1];
        if(tradeList[lastTradeId].state != TradeState.ACCEPTING) return (2**64 - 1);
        return lastTradeId;
    }

     function revokeMyProposal(uint id) public {
        uint proposeId = lendMap[msg.sender][id];
        if(proposalList[proposeId].state != ProposalState.WAITING) return;
        uint tradeId = proposalList[proposeId].tradeId;
        if(tradeList[tradeId].state == TradeState.ACCEPTING) {
            // Lender wishes to revoke his ETH when proposal is still WAITING
            proposalList[proposeId].state = ProposalState.REPAID;
            msg.sender.transfer(proposalList[proposeId].amount);
        }
        else if(tradeList[tradeId].state == TradeState.LOCKED) {
            // The trade is locked/accepting and the due date passed : transfer the mortgage
            if(tradeList[tradeId].dueDate < now) return;
            tradeList[tradeId].state = TradeState.FAILED;
            for(uint i = 0; i < tradeList[tradeId].proposalCount; i++) {
                uint numI = tradeList[tradeId].proposal[i];
                if(proposalList[numI].state == ProposalState.ACCEPTED) {
                    // transfer mortgage 
                }
            } 
        }
    }

     function lockTrade(uint tradeId) public {
        //contract will send money to msg.sender
        //states of proposals would be finalized, not accepted proposals would be reimbursed
        if(tradeList[tradeId].state == TradeState.ACCEPTING)
        {
          tradeList[tradeId].state = TradeState.LOCKED;
          for(uint i = 0; i < tradeList[tradeId].proposalCount; i++)
          {
            uint numI = tradeList[tradeId].proposal[i];
            if(proposalList[numI].state == ProposalState.ACCEPTED)
            {
              msg.sender.transfer(proposalList[numI].amount); //Send to borrower
            }
            else
            {
              proposalList[numI].state = ProposalState.REPAID;
              proposalList[numI].lender.transfer(proposalList[numI].amount); //Send back to lender
            }
          }
        }
        else
          return;
    }
    
    //Amount to be Repaid
     function getRepayValue(uint tradeId) public view returns(uint) {
        if(tradeList[tradeId].state == TradeState.LOCKED)
        {
          uint time = tradeList[tradeId].startDate;
          uint finalamount = 0;
          for(uint i = 0; i < tradeList[tradeId].proposalCount; i++)
          {
            uint numI = tradeList[tradeId].proposal[i];
            if(proposalList[numI].state == ProposalState.ACCEPTED)
            {
              uint original = proposalList[numI].amount;
              uint rate = proposalList[numI].rate;
              uint now = block.timestamp;
              uint interest = (original*rate*(now - time))/(365*24*60*60*100);
              finalamount += interest;
              finalamount += original;
            }
          }
          return finalamount;
        }
        else
          return (2**64 -1);
    }

     function repayTrade(uint tradeId) public payable {
      uint now = block.timestamp;
      uint toBePaid = getRepayValue(tradeId);
      uint time = tradeList[tradeId].startDate;
      uint paid = msg.value;
      if(paid >= toBePaid)
      {
        uint remain = paid - toBePaid;
        tradeList[tradeId].state = TradeState.SUCCESSFUL;
        for(uint i = 0; i < tradeList[tradeId].proposalCount; i++)
        {
          uint numI = tradeList[tradeId].proposal[i];
          if(proposalList[numI].state == ProposalState.ACCEPTED)
          {
            uint original = proposalList[numI].amount;
            uint rate = proposalList[numI].rate;
            uint interest = (original*rate*(now - time))/(365*24*60*60*100);
            uint finalamount = interest + original;
            proposalList[numI].lender.transfer(finalamount);
            proposalList[numI].state = ProposalState.REPAID;
          }
        }
        msg.sender.transfer(remain);
      }
      else
      {
        msg.sender.transfer(paid);
      }
    }

     function acceptProposal(uint proposeId) public
    {
        uint tradeId = getActiveTradeId(msg.sender); 
        if(tradeId == (2**64 - 1)) return;
        Proposal storage pObj = proposalList[proposeId];
        if(pObj.state != ProposalState.WAITING) return;

        Trade storage lObj = tradeList[tradeId];
        if(lObj.state != TradeState.ACCEPTING) return;

        if(lObj.collected + pObj.amount <= lObj.amount)
        {
          tradeList[tradeId].collected += pObj.amount;
          proposalList[proposeId].state = ProposalState.ACCEPTED;
        }
    }

     function totalProposalsBy(address lender) public view returns(uint) {
        return lendMap[lender].length;
    }

     function getProposalAtPosFor(address lender, uint pos) public view returns(address, uint, ProposalState, uint, uint, uint, uint, bytes32) {
        Proposal storage prop = proposalList[lendMap[lender][pos]];
        return (prop.lender, prop.tradeId, prop.state, prop.rate, prop.amount, tradeList[prop.tradeId].amount, tradeList[prop.tradeId].dueDate, tradeList[prop.tradeId].mortgage);
    }

// BORROWER ACTIONS    

     function totalTradesBy(address borrower) public view returns(uint) {
        return tradeMap[borrower].length;
    }

     function getTradeDetailsByAddressPosition(address borrower, uint pos) public view returns(TradeState, uint, uint, uint, uint,bytes32) {
        Trade storage obj = tradeList[tradeMap[borrower][pos]];
        return (obj.state, obj.dueDate, obj.amount, obj.collected, tradeMap[borrower][pos], obj.mortgage);
    }

     function getLastTradeState(address borrower) public view returns(TradeState) {
        uint tradeLength = tradeMap[borrower].length;
        if(tradeLength == 0)
            return TradeState.SUCCESSFUL;
        return tradeList[tradeMap[borrower][tradeLength -1]].state;
    }

     function getLastTradeDetails(address borrower) public view returns(TradeState, uint, uint, uint, uint) {
        uint tradeLength = tradeMap[borrower].length;
        Trade storage obj = tradeList[tradeMap[borrower][tradeLength -1]];
        return (obj.state, obj.dueDate, obj.amount, obj.proposalCount, obj.collected);
    }

     function getProposalDetailsByTradeIdPosition(uint tradeId, uint numI) public view returns(ProposalState, uint, uint, uint, address) {
        Proposal storage obj = proposalList[tradeList[tradeId].proposal[numI]];
        return (obj.state, obj.rate, obj.amount, tradeList[tradeId].proposal[numI],obj.lender);
    }

     function numTotalTrades() public view returns(uint) {
        return tradeList.length;
    }
    
}
