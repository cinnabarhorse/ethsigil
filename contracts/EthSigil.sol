pragma solidity ^0.6.8;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EthSigil is ERC721, Ownable {
    address payable tributeAddress; //Address that will receive ETH tribute when Sigils are burned

    address payable burnAddress = 0x0000000000000000000000000000000000000000;
    uint256 minimumCharge = 10000000000000000;
    bool transferEnabled = false;

    struct Charge {
        uint256 amount;
        uint256 date;
        address charger;
    }

    struct SigilData {
        address caster;
        bool alive;
        uint256 chargingPeriod;
        uint256 charge;
        uint256 chargeCount;
        uint256 createdOn;
        string imgHash;
        string incantation;
    }

    mapping(uint256 => Charge[]) chargesByTokenId; /**@dev Keeps track of all charges
    SigilData[] sigils; /**@dev Keeps track of all sigils */

    /**@dev Events  */
    event SigilCreated(address indexed _from, uint256 indexed _sigilId);
    event SigilCharged(
        address indexed _from,
        uint256 indexed _sigilId,
        uint256 _amount
    );
    event SigilBurned(address indexed _from, uint256 indexed _sigilId);

    /**
    @dev Constructor function. Sets ERC721 values and tribute address
    */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        address payable _tributeAddress
    ) public ERC721(_name, _symbol) {
        //isOnline = true;
        _setBaseURI(_baseURI);
        tributeAddress = _tributeAddress;
    }

    /***********************************|
   |             Only owner             |
   |__________________________________*/

    function updateTributeAddress(address payable _tributeAddress)
        external
        onlyOwner
    {
        tributeAddress = _tributeAddress;
    }

    function updateMinimumCharge(uint256 _amount) external onlyOwner {
        minimumCharge = _amount;
    }

    function updateTransferEnabled(bool _transferEnabled) external onlyOwner {
        transferEnabled = _transferEnabled;
    }

    /***********************************|
   |          Public read               |
   |__________________________________*/

    function getSigilCharges(uint256 _tokenId) public view returns (uint256) {
        Charge[] storage charges = chargesByTokenId[_tokenId];
        return charges.length;
    }

    function getCharge(uint256 _tokenId, uint256 _chargeId)
        public
        view
        returns (
            address charger,
            uint256 amount,
            uint256 date
        )
    {
        Charge[] memory charges = chargesByTokenId[_tokenId];
        Charge memory charge = charges[_chargeId];
        charger = address(charge.charger);
        amount = uint256(charge.amount);
        date = uint256(charge.date);
    }

    function getSigil(uint256 _tokenId)
        public
        view
        returns (
            uint256 chargingPeriod,
            uint256 charge,
            uint256 chargeCount,
            bool alive,
            address caster,
            uint256 createdOn,
            string memory imgHash,
            string memory incantation
        )
    {
        SigilData memory sigil = sigils[_tokenId];
        charge = uint256(sigil.charge);
        chargingPeriod = uint256(sigil.chargingPeriod);
        chargeCount = uint256(sigil.chargeCount);
        alive = bool(sigil.alive);
        caster = address(sigil.caster);
        createdOn = uint256(sigil.createdOn);
        imgHash = string(sigil.imgHash);
        incantation = string(sigil.incantation);
    }

    function getSigilsByCaster(address _owner)
        external
        view
        returns (uint256[] memory ownerSigils)
    {
        //Iterate through all sigils and return IDs of sigils that belong to owner
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalSigils = sigils.length - 1;
            uint256 resultIndex = 0;

            // We count on the fact that all cats have IDs starting at 1 and increasing
            // sequentially up to the totalCat count.
            uint256 sigilId;

            for (sigilId = 0; sigilId <= totalSigils; sigilId++) {
                if (_exists(sigilId) && ownerOf(sigilId) == _owner) {
                    result[resultIndex] = sigilId;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    function getRemainingTime(uint256 _tokenId) public view returns (uint256) {
        return sigils[_tokenId].chargingPeriod.sub(now);
    }

    /***********************************|
   |            Sigil functions         |
   |__________________________________*/

    /**
    @dev Creates a new sigil.
    @param _chargingPeriod Amount of time before the sigil can be burned. Expressed in days.
    @param _imgHash The txId from ARWeave or IPFS
    @param _incantation //The Sigil's message
    */
    function createSigil(
        uint256 _chargingPeriod,
        string memory _imgHash,
        string memory _incantation
    ) public payable {
        require(msg.value >= minimumCharge, "initial charge too low");

        SigilData memory newSigil = SigilData({
            chargingPeriod: now + _chargingPeriod * 1 days,
            charge: msg.value,
            chargeCount: 1,
            alive: true,
            caster: msg.sender,
            createdOn: now,
            imgHash: _imgHash,
            incantation: _incantation
        });

        sigils.push(newSigil);

        uint256 newSigilId = sigils.length - 1;
        _safeMint(msg.sender, newSigilId);
        emit SigilCreated(msg.sender, newSigilId);
    }

    /**
    @dev Charges a sigil.
    @param _tokenId the tokenID to charge 
    */

    function chargeSigil(uint256 _tokenId) public payable {
        require(msg.value > 0, "Not enough charge");

        SigilData storage sigil = sigils[_tokenId];
        sigil.charge = sigil.charge.add(msg.value);
        sigil.chargeCount = sigil.chargeCount.add(1);

        Charge[] storage charges = chargesByTokenId[_tokenId];
        Charge memory newCharge = Charge({
            charger: msg.sender,
            amount: msg.value,
            date: now
        });
        charges.push(newCharge);
        emit SigilCharged(msg.sender, _tokenId, msg.value);
    }

    /**
    @dev Burns a sigil and the ETH contained within. Transfers 5% of the charged ETH to EthSigil, 5% to the burner, and 90% to the burn address.
    @param _tokenId the tokenID to burn 
    */

    function burnSigil(uint256 _tokenId) public {
        SigilData storage sigil = sigils[_tokenId];
        require(sigil.alive, "Sigil already burned");
        require(now >= sigil.chargingPeriod, "Charging period not finished");
        require(
            msg.sender == sigil.caster ||
                (msg.sender != sigil.caster &&
                    now >= sigil.chargingPeriod + 72 hours),
            "Cannot burn yet!"
        );

        uint256 amount = sigil.charge;
        uint256 ethSigiltribute = amount.div(20); //5% to EthSigil

        uint256 burnerTribute = amount.div(20); //5% to burner
        uint256 burned = amount.mul(9).div(10); //90% burned

        sigil.alive = false;
        sigil.charge = 0;
        sigil.chargeCount = 0;

        tributeAddress.transfer(ethSigiltribute);
        msg.sender.transfer(burnerTribute);
        burnAddress.transfer(burned);
        _burn(_tokenId);
        emit SigilBurned(msg.sender, _tokenId);
    }

    /**
    @dev Transfers the Sigil to a new owner. Only possible if transferEnabled is true.
    @param from from address
    @param to to address
    @param tokenId token to transfer
    */

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        if (transferEnabled == false) {
            revert("Transfer disabled");
        } else {
            super.safeTransferFrom(from, to, tokenId);
        }
    }

    /**
    @dev Transfers the Sigil to a new owner. Only possible if transferEnabled is true.
    @param from from address
    @param to to address
    @param tokenId token to transfer
    */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length

        if (transferEnabled == false) {
            revert("Transfer disabled");
        } else {
            super.transferFrom(from, to, tokenId);
        }
    }
}
