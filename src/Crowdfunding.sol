// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// 项目状态
enum ProjectState {
    None, // 代替null
    Active, // 募集中
    Success, // 募集成功
    Failed, // 募集失败
    Closed //提款后，关闭。
}

// 单个项目。 contract 比 struct 更好。
contract ProjectInfoContract {
    // 这些是基本信息。 可以聚合为 struct
    address owner; // 所有者。
    string public title; // 标题。
    uint deadline; // 截止时间。秒。
    uint public goal; // 目标金额。单位wei
    bool goalCanExceed; // 是否能超过goal
    string public descUrl; // 描述信息。

    uint sumDonate = 0; // 把捐款都累加。返还多余钱，需要这个。
    ProjectState state; // 当前状态。
    mapping(address => uint) donateMap; // 每个人的出款

    // 事件
    event NewProject(address indexed owner, uint goal, string title);
    event StateChanged(ProjectState stateFrom, ProjectState stateTo); // 状态改变了。

    // 事件不需要project，前端监听已经知道合约实例了。
    event Donated(address indexed user, uint money, uint sumMoney); // 某人出钱了。
    event Refunded(address indexed user, uint money); // 某人退款了。
    event Withdrawed(address indexed user, uint money); // 某人取款了

    using Strings for uint;

    // 构造函数
    constructor(
        address _owner, // 任何人都可以发起众筹。
        string memory _title,
        uint _deadline,
        uint _goal,
        bool _goalCanExceed,
        string memory _descUrl
    ) {
        require(_owner != address(0), "_owner is invalid");
        require(_deadline > block.timestamp, "_deadline is invalid");
        require(_goal > 0, "_goal must be greater than 0");
        require(bytes(_descUrl).length > 0, "_descUrl is invalid");

        // this.owner = _owner; // 错误。 this 不能引用变量，可以引用方法。
        owner = _owner; // 正确。直接给变量赋值。
        title = _title;
        deadline = _deadline;
        goal = _goal;
        goalCanExceed = _goalCanExceed;
        descUrl = _descUrl;
        state = ProjectState.Active; // 进行中。

        // 事件。
        // emit StateChanged(address(this),null,  state);// 错误。 没有null
        emit StateChanged(ProjectState.None, state);
        emit NewProject(owner, goal, title);
    }

    // 状态机模式。
    modifier needState(ProjectState _state) {
        _needState(_state);
        _;
    }

    function _needState(ProjectState _state) internal view {
        require(state == _state, "state not valid");
    }

    // 转字符串。
    function toString() public view returns (string memory) {
        // 入参只能是 string
        string memory str = string.concat(
            " title= ",
            title,
            " goal= ",
            goal.toString(),
            " owner= ",
            Strings.toHexString(owner),
            " addr= ",
            // uint(address).toString()// 错误。不能直接从 addr转 uint
            Strings.toHexString(address(this)),
            " descUrl= ",
            descUrl
        );
        return (str);
    }

    // 只查询目标金额。
    function queryGoal() public view returns (uint) {
        return goal;
    }

    // 查询项目信息。
    function queryInfo()
        public
        view
        returns (
            address owner_,
            string memory title_,
            uint deadline_,
            uint goal_,
            string memory descUrl_,
            ProjectState state_
        )
    {
        return (owner, title, deadline, goal, descUrl, state);
    }

    // 查询某人的出款
    function queryDonate() public view returns (uint) {
        address addr = msg.sender;
        require(addr != address(0), "addr is not valid");
        uint money = donateMap[addr];
        return (money);
    }

    // 某个人出款
    function donate() public payable needState(ProjectState.Active) {
        address user = msg.sender; // 人
        uint money = msg.value; // 金额
        // 验证
        require(user != address(0), "addr is not valid");
        require(money > 0, "money is invalid");
        require(user.balance >= money, "addr has not enougth money");
        require(block.timestamp <= deadline, "deadline reached");

        // 需要的金钱。

        // 在进入方法之前， address(this).balance 已经被修改了。 这里再判断，就是事后了。
        // uint needMoney = goal - address(this).balance; // 错误。uint是无符号数，不能表示负数。
        uint needMoney = goal - sumDonate; // 独立计算一个变量。

        // 用户可能给多了。
        uint money2 = money;
        if (!goalCanExceed && money > needMoney) {
            money2 = needMoney;
        }

        // 改内部状态
        // 每个人的钱
        donateMap[user] += money2;
        sumDonate += money2;

        // 判断累计金额
        // this.checkState(); // this 可以调用方法。 使用 CALL，gas 高，会改变 msg.sender
        checkState(); // 内部调用。推荐。

        // 与外部交互。
        emit Donated(user, money2, sumDonate); // 事件。
        // addr.balance = addr.balance - money; // 错误。这个是只读的。

        // 给多了，就退回。
        if (!goalCanExceed && money > needMoney) {
            uint backMoney = money - needMoney;
            (bool success, ) = msg.sender.call{value: backMoney}("");
            require(success, "back money error");
            emit Refunded(msg.sender, backMoney); // 事件。
        }
    }

    // 检测状态。 成功或失败。 内部、外部都触发调用。及时改状态。
    function checkState() public returns (ProjectState) {
        // 先判断状态。
        if (state == ProjectState.Active) {
            if (address(this).balance >= goal) {
                state = ProjectState.Success; // 成功了。
                emit StateChanged(ProjectState.Active, state);
                return state;
            }
            if (block.timestamp > deadline) {
                state = ProjectState.Failed; // 失败了。
                emit StateChanged(ProjectState.Active, state);
                return state;
            }
        }
        return state;
    }

    // 某个人退款
    function refund() public needState(ProjectState.Failed) {
        require(msg.sender != address(0), "addr invalid");
        uint money = donateMap[msg.sender];
        require(money > 0, "donate money not found");

        // 删除金额。
        delete donateMap[msg.sender];

        // 把钱转出。
        (bool success, ) = payable(msg.sender).call{value: money}("");
        require(success, "refund error");

        // 事件
        emit Refunded(msg.sender, money);
    }

    // 取款。成功才能取款。 只有owner才能取款。
    function withdraw() public needState(ProjectState.Success) {
        require(owner == msg.sender, "not owner");
        uint moneySum = address(this).balance;
        require(moneySum > 0, "sumMoney invalid");

        // 改状态
        state = ProjectState.Closed;
        emit StateChanged(ProjectState.Success, state);

        // 把钱发给owner。
        // payable(owner).call{msg.value: money}("");// 错误。 是 {value:xxx}
        (bool success, ) = payable(owner).call{value: moneySum}(""); // 正确。
        require(success, "withdraw error");

        // 事件
        emit Withdrawed(owner, moneySum);
    }
}

// 工厂合约
contract ProjectFactoryContract {
    // 这些集合，是工厂的必须项。管理多个项目。
    mapping(address => ProjectInfoContract) addrProjectMap; // key=项目的地址
    mapping(address => address[]) userProjectMap; // key=用户的地址

    // 创建一个项目。
    // 用户调用工厂合约的 createCampaign 函数（内部用 new）动态创建自己的众筹项目
    function createProject(
        string memory _title,
        uint _deadline,
        uint _goal,
        bool _goalCanExceed,
        string memory _descUrl
    ) public returns (address projectAddr_) {
        // 任何人都可以发起众筹。
        address _owner = msg.sender; // owner
        ProjectInfoContract project = new ProjectInfoContract(
            _owner,
            _title,
            _deadline,
            _goal,
            _goalCanExceed,
            _descUrl
        );

        // 返回地址。即为ID。
        address projectAddr = address(project);

        // 存入集合
        addrProjectMap[projectAddr] = project;
        userProjectMap[_owner].push(projectAddr);
        return projectAddr;
    }

    // 查询我的项目。
    function queryMyProject()
        public
        view
        returns (ProjectInfoContract[] memory)
    {
        address[] storage addrList = userProjectMap[msg.sender];
        uint len = addrList.length;
        ProjectInfoContract[] memory projectList = new ProjectInfoContract[](
            len
        );

        if (len > 0) {
            // for (address addr : addrList){// 错误。没有这个用法。
            // for (address addr in addrList){// 错误。没有这个用法。
            // 正确。
            for (uint k = 0; k < len; k++) {
                address tmp = addrList[k];
                ProjectInfoContract project = addrProjectMap[tmp];
                projectList[k] = project;
            }
        }
        return (projectList);
    }
}
