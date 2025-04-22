import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

contract PausableShare is DaoAuthorizable {
    bool public mintsPaused;
    bool public burnsPaused;

    error NotAuthorized();
    error SharesPaused();

    constructor(IDAO _dao) DaoAuthorizable(_dao) {}

    function pauseMints() public {
        if (msg.sender != address(dao())) revert NotAuthorized();
        // Pause mints logic
        mintsPaused = true;
    }

    function pauseBurns() public {
        if (msg.sender != address(dao())) revert NotAuthorized();
        // Pause burns logic
        burnsPaused = true;
    }

    function unpauseMints() public {
        if (msg.sender != address(dao())) revert NotAuthorized();
        // Unpause mints logic
        mintsPaused = false;
    }

    function unpauseBurns() public {
        if (msg.sender != address(dao())) revert NotAuthorized();
        // Unpause burns logic
        burnsPaused = false;
    }

    function pause() external {
        pauseMints();
        pauseBurns();
    }

    function unpause() external {
        unpauseMints();
        unpauseBurns();
    }
}
