pragma solidity ^0.4.11;

// ----------------------------------------------------------------------------
// OAX 'openANX Token' crowdfunding contract
//
// Refer to http://openanx.org/ for further information.
//
// Enjoy. (c) openANX and BokkyPooBah / Bok Consulting Pty Ltd 2017. 
// The MIT Licence.
// ----------------------------------------------------------------------------

import "./ERC20Interface.sol";
import "./Owned.sol";
import "./SafeMath.sol";
import "./LockedTokens.sol";

// ----------------------------------------------------------------------------
// ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract ERC20Token is ERC20Interface, Owned {
    using SafeMath for uint;

    string public symbol;
    string public name;
    uint8 public decimals;

    // ------------------------------------------------------------------------
    // Balances for each account
    // ------------------------------------------------------------------------
    mapping(address => uint) balances;

    // ------------------------------------------------------------------------
    // Owner of account approves the transfer of an amount to another account
    // ------------------------------------------------------------------------
    mapping(address => mapping (address => uint)) allowed;

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function ERC20Token(
        string _symbol, 
        string _name, 
        uint8 _decimals, 
        uint _totalSupply
    ) Owned() {
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balances[owner] = _totalSupply;
    }

    // ------------------------------------------------------------------------
    // Get the account balance of another account with address _owner
    // ------------------------------------------------------------------------
    function balanceOf(address _owner) constant returns (uint balance) {
        return balances[_owner];
    }

    // ------------------------------------------------------------------------
    // Transfer the balance from owner's account to another account
    // ------------------------------------------------------------------------
    function transfer(address _to, uint _amount) returns (bool success) {
        if (balances[msg.sender] >= _amount             // User has balance
            && _amount > 0                              // Non-zero transfer
            && balances[_to] + _amount > balances[_to]  // Overflow check
        ) {
            balances[msg.sender] = balances[msg.sender].sub(_amount);
            balances[_to] = balances[_to].add(_amount);
            Transfer(msg.sender, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    // ------------------------------------------------------------------------
    // Allow _spender to withdraw from your account, multiple times, up to the
    // _value amount. If this function is called again it overwrites the
    // current allowance with _value.
    // ------------------------------------------------------------------------
    function approve(
        address _spender,
        uint _amount
    ) returns (bool success) {
        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    // ------------------------------------------------------------------------
    // Spender of tokens transfer an amount of tokens from the token owner's
    // balance to another account. The owner of the tokens must already
    // have approve(...)-d this transfer
    // ------------------------------------------------------------------------
    function transferFrom(
        address _from,
        address _to,
        uint _amount
    ) returns (bool success) {
        if (balances[_from] >= _amount                  // From a/c has balance
            && allowed[_from][msg.sender] >= _amount    // Transfer approved
            && _amount > 0                              // Non-zero transfer
            && balances[_to] + _amount > balances[_to]  // Overflow check
        ) {
            balances[_from] = balances[_from].sub(_amount);
            allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
            balances[_to] = balances[_to].add(_amount);
            Transfer(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(
        address _owner, 
        address _spender
    ) constant returns (uint remaining) {
        return allowed[_owner][_spender];
    }
}


// ----------------------------------------------------------------------------
// openANX crowdsale token smart contract
// ----------------------------------------------------------------------------
contract OpenANXToken is ERC20Token, OpenANXTokenConfig {

    bool public finalised = false;

    // Number of ethers per token. This can be adjusted as the ETH/USD rate
    // changes. And event is logged when this rate is updated
    // ETH per token 0.00290923 indicative at 8 June 2017
    // 1 ETH = 1 / 0.00290923 = 343.733565238912015 OAX
    // tokensPerEther = 343.733565238912015
    // tokensPerKEther = 343,733.565238912015
    // tokensPerKEther = 343,734 rounded to an uint, six significant figures
    uint public tokensPerKEther = 343734;

    // Locked Tokens
    LockedTokens public lockedTokens;

    // Wallet receiving the raised funds 
    address public wallet;

    // ------------------------------------------------------------------------
    // KYC is required before the crowdsale participants can transfer their
    // tokens
    // ------------------------------------------------------------------------
    mapping(address => bool) public kycRequired;


    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function OpenANXToken(address _wallet) 
        ERC20Token(SYMBOL, NAME, DECIMALS, 0)
    {
        wallet = _wallet;
    }

    // ------------------------------------------------------------------------
    // Change wallet address
    // Can be set at any time by the owner
    // ------------------------------------------------------------------------
    function setWallet(address _wallet) onlyOwner {
        wallet = _wallet;
        WalletUpdated(wallet);
    }
    event WalletUpdated(address newWallet);

    // ------------------------------------------------------------------------
    // Set number of tokens per 1,000 ETH
    // Can only be set before the start of the crowdsale, by the owner
    // ------------------------------------------------------------------------
    function setTokensPerKEther(uint _tokensPerKEther) onlyOwner {
        if (now >= START_DATE) throw;
        if (_tokensPerKEther == 0) throw;
        tokensPerKEther = _tokensPerKEther;
        TokensPerKEtherUpdated(tokensPerKEther);
    }
    event TokensPerKEtherUpdated(uint tokensPerKEther);

    // ------------------------------------------------------------------------
    // Accept ethers to buy tokens during the crowdsale
    // ------------------------------------------------------------------------
    function () payable {
        // No contributions after finalised
        if (finalised) throw;
        // No contributions before start
        if (now < START_DATE) throw;
        // No contributions after end
        if (now > END_DATE) throw;
        // No contributions below the minimum (can be 0 ETH)
        if (msg.value == 0 || msg.value < CONTRIBUTIONS_MIN) throw;
        // No contributions above a maximum (if maximum is set to non-0)
        if (CONTRIBUTIONS_MAX > 0 && msg.value > CONTRIBUTIONS_MAX) throw;

        // `18` is the ETH decimals, `- decimals` is the token decimals
        // and `+ 3` for the KEther factor
        uint tokens = msg.value * tokensPerKEther / 10**uint(18 - decimals + 3);
        if (totalSupply + tokens > TOKENS_HARD_CAP * DECIMALSFACTOR) throw;

        balances[msg.sender] = balances[msg.sender].add(tokens);
        totalSupply = totalSupply.add(tokens);
        Transfer(0x0, msg.sender, tokens);
        TokensBought(msg.sender, msg.value, this.balance, tokens,
             totalSupply, tokensPerKEther);
        kycRequired[msg.sender] = true;
        // Transfer the contributed ethers
        if (!wallet.send(msg.value)) throw;
    }
    event TokensBought(address indexed buyer, uint ethers, 
        uint newEtherBalance, uint tokens, uint newTotalSupply, 
        uint tokensPerKEther);

    // ------------------------------------------------------------------------
    // Finalise by adding the locked tokens to this contract and total supply
    // ------------------------------------------------------------------------
    function finalise() {
        // Can only finalise if raised > soft cap or after the end date
        if (totalSupply < TOKENS_SOFT_CAP * DECIMALSFACTOR && now < END_DATE) throw;
        // Can only finalise once
        if (finalised) throw;
        lockedTokens = new LockedTokens(this);
        // Allocate locked and premined tokens
        balances[this] = balances[this].add(lockedTokens.totalSupplyLocked());
        totalSupply = totalSupply.add(lockedTokens.totalSupplyLocked());
        finalised = true;
    }

    // ------------------------------------------------------------------------
    // Precommitment funding tokens can be added before the crowdsale starts
    // ------------------------------------------------------------------------
    function addPrecommitment(address participant, uint balance) onlyOwner {
        if (now >= START_DATE) throw;
        if (balance == 0) throw;
        balances[participant] = balances[participant].add(balance);
        Transfer(0x0, participant, balance);
    }
    event PrecommitmentAdded(address indexed participant, uint balance);

    // ------------------------------------------------------------------------
    // Transfer the balance from owner's account to another account, with KYC
    // ------------------------------------------------------------------------
    function transfer(address _to, uint _amount) returns (bool success) {
        if (kycRequired[_to]) throw;
        return super.transfer(_to, _amount);
    }

    // ------------------------------------------------------------------------
    // Spender of tokens transfer an amount of tokens from the token owner's
    // balance to another account, with KYC
    // ------------------------------------------------------------------------
    function transferFrom(address _from, address _to, uint _amount) 
        returns (bool success)
    {
        if (kycRequired[_from]) throw;
        return super.transferFrom(_from, _to, _amount);
    }

    // ------------------------------------------------------------------------
    // Participant has been KYC verified
    // ------------------------------------------------------------------------
    function kycVerify(address participant) onlyOwner {
        kycRequired[participant] = false;
        KycVerified(participant);
    }
    event KycVerified(address indexed participant);

    // ------------------------------------------------------------------------
    // Transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint amount)
      onlyOwner returns (bool success) 
    {
        return ERC20Interface(tokenAddress).transfer(owner, amount);
    }
}