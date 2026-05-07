// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
    ProjectState,
    ProjectInfoContract,
    ProjectFactoryContract
} from "../src/Crowdfunding.sol";

contract ProjectXTest is Test {
    // 工厂合约。
    ProjectFactoryContract public factory;

    // 默认的项目。
    address projectOwner = address(0x3003);
    address projectAddrCanExceed; // 金额可以超过。
    address projectAddrNotExceed; // 金额不能超过。

    // 多个人。
    address addrJack = address(0x6006);
    address addrTom = address(0x7007);

    // 每次执行test，都会执行这个函数。
    function setUp() public {
        // 工厂
        factory = new ProjectFactoryContract();
        // mock。
        deal(projectOwner, 0);
        // 项目
        vm.startPrank(projectOwner);
        projectAddrCanExceed = factory.createProject(
            "buy 2000 apple",
            block.timestamp + 1 minutes,
            100 wei,
            true, // 可以超过金额。
            "http://hello.com/apple.json"
        );
        projectAddrNotExceed = factory.createProject(
            "buy 1000 tree",
            block.timestamp + 1 minutes,
            100 wei,
            false, // 不能超过金额。
            "http://hello.com/apple.json"
        );
        vm.stopPrank();

        console.log(unicode"初始化： ");
        console.log(unicode"  当前时间 : ", block.timestamp);
        console.log("  factory Addr : ", address(factory));
        console.log("  projectAddrCanExceed : ", projectAddrCanExceed);
        console.log("  projectAddrNotExceed : ", projectAddrNotExceed);

        // 设置余额。钱不够会触发异常。
        deal(projectOwner, 0);
        deal(addrJack, 500);
        deal(addrTom, 600);

        console.log(unicode"projectOwner 余额 = ", projectOwner.balance);
        console.log(unicode"addrJack 余额 = ", addrJack.balance);
        console.log(unicode"addrTom  余额 = ", addrTom.balance);
        console.log("-------------");
    }

    // 测试工厂。
    function test_factory() public {
        // jack没有项目。
        vm.prank(addrJack);
        ProjectInfoContract[] memory jackProjects = factory.queryMyProject();
        assert(jackProjects.length == 0);
        console.log(unicode" jack 没有项目。");

        // owner有项目。
        vm.prank(projectOwner);
        ProjectInfoContract[] memory ownerProjects = factory.queryMyProject();
        assert(ownerProjects.length > 0);
        console.log(unicode" projectOwner 有项目。 ");
        for (uint k = 0; k < ownerProjects.length; k++) {
            ProjectInfoContract tmp = ownerProjects[k];
            console.log(unicode"项目： ", tmp.toString());
        }
    }

    // 新建，查询
    function test_createQuery() public {
        // vm.expectEmit(true, true, true, true);// 这个方法有什么问题
        address addrBob = address(200002);
        vm.prank(addrBob);
        address projectAddr = factory.createProject(
            "buy 555 banana",
            block.timestamp + 1 minutes,
            100 wei,
            true,
            "http://hello.com/banana.json"
        );
        console.log(unicode"新的项目地址 = ", projectAddr);

        // 转成合约。
        ProjectInfoContract projectInfo = ProjectInfoContract(projectAddr);

        // 查询明细。
        (
            address owner_,
            string memory title_,
            uint deadline_,
            uint goal_,
            string memory descUrl_,
            ProjectState state_
        ) = projectInfo.queryInfo();
        // 错误。不能打印枚举。
        // 错误。不支持多种类型混合。
        console.log(unicode"查询明细：");
        console.log("  owner_ : ", owner_);
        console.log("  title_ : ", title_);
        console.log("  deadline_ : ", deadline_);
        console.log("  goal_ : ", goal_);
        console.log("  descUrl_ : ", descUrl_);
        console.log("  state_ : ", uint(state_));

        require(owner_ == addrBob, "owner not match");

        // 查询某人的额。
        uint money = projectInfo.queryDonate();
        console.log("queryDonate : ", money);
        require(money == 0, "queryDonate error ");
    }

    // 普通的捐款。每个人可以捐多次。 金额可以超过。
    function test_donateCanExceed() public {
        // 多个人参与众筹。
        ProjectInfoContract project = ProjectInfoContract(projectAddrCanExceed);

        // jack 调用众筹函数。
        uint sendJack1 = 22;
        vm.prank(addrJack);
        project.donate{value: sendJack1}();

        // tom 调用众筹函数。
        uint sendTom1 = 31;
        vm.prank(addrTom);
        project.donate{value: sendTom1}();

        console.log(unicode"donate之后，addrJack 余额 = ", addrJack.balance);
        console.log(unicode"donate之后，addrTom  余额 = ", addrTom.balance);

        // 查出款。
        vm.prank(addrJack);
        uint donateJack = project.queryDonate();
        vm.prank(addrTom);
        uint donateTom = project.queryDonate();
        console.log(unicode"addrJack  出款 = ", donateJack);
        console.log(unicode"donateTom 出款 = ", donateTom);
        require(sendJack1 == donateJack, "jack donate not match");
        require(sendTom1 == donateTom, "tom donate not match");

        ProjectState state1 = project.checkState();
        console.log(unicode"钱还不够，当前state = ", uint(state1));
        require(state1 == ProjectState.Active, "state not match");

        // 金额还没满。状态还没变。
        // project.refund();// 错误。[Revert] state not valid
        // project.withdraw(); // 错误。[Revert] state not valid

        // 继续出款。
        uint donateJack2 = 88;
        vm.prank(addrJack);
        project.donate{value: donateJack2}();

        // 金额达到了。
        ProjectState state2 = project.checkState();
        console.log(unicode"jack又出钱了。钱够了，当前state = ", uint(state2));
        require(state2 == ProjectState.Success, "state not match");

        // project.refund(); // 错误。 已经成功了，不能退款。 [Revert] state not valid
        // project.withdraw();// 错误。 [Revert] not owner

        // 取款。
        console.log(unicode"取款前，owner余额 = ", projectOwner.balance);
        vm.prank(projectOwner);
        project.withdraw();
        console.log(unicode"取款后，owner余额 = ", projectOwner.balance);

        // 判断金额相等。
        require(
            projectOwner.balance == (donateJack + donateTom + donateJack2),
            "withdraw not match"
        );
    }

    // 捐款，金额不能超过。
    function test_donateNotExceed() public {
        ProjectInfoContract project = ProjectInfoContract(projectAddrNotExceed);

        // 只查询目标金额。
        uint goal = project.queryGoal();
        uint jackBalanceBefore = addrJack.balance;

        // 捐几次。
        vm.startPrank(addrJack);
        project.donate{value: 33}();
        project.donate{value: 41}();
        project.donate{value: 56}(); // 有退款。 emit Refunded(addr: 0x0000000000000000000000000000000000006006, money: 30)
        // project.donate{value: 11}(); // 错误。金额已经满了。 [Revert] state not valid
        vm.stopPrank();

        console.log(unicode"捐款后，jack的余额 = ", addrJack.balance);
        // 金额差值等于goal
        require(
            // 使用require
            addrJack.balance + goal == jackBalanceBefore,
            "jack balance not match goal"
        );
        assert(addrJack.balance + goal == jackBalanceBefore); // 使用assert

        console.log(
            unicode"在满了之后，项目的余额 = ",
            address(project).balance
        );
        // 金额不能超。
        require(address(project).balance == goal, "goal not match");

        // owner取款。
        console.log(unicode"取款前，owner的余额 = ", projectOwner.balance);
        vm.prank(projectOwner);
        project.withdraw(); // 取款。
        console.log(unicode"取款后，owner的余额 = ", projectOwner.balance);
        require(goal == projectOwner.balance, "owner balance not match goal");
    }

    // 测试时间过期了。 退款。
    function test_deadlineRefund() public {
        ProjectInfoContract project = ProjectInfoContract(projectAddrCanExceed);
        uint jackBalanceBefore = addrJack.balance;

        // 捐款。
        vm.startPrank(addrJack);
        project.donate{value: 10}();
        project.donate{value: 20}();
        project.donate{value: 30}();
        vm.stopPrank();
        console.log(unicode"捐款后，jack的余额 = ", addrJack.balance);

        // 模拟deadline超时了。
        // vm.skip(5 minutes); // 超时。 错误。没有skip函数。
        vm.warp(block.timestamp + 5 minutes); // 超时。
        ProjectState state1 = project.checkState();
        assert(state1 == ProjectState.Failed);

        // 退款。
        vm.prank(addrJack);
        project.refund();
        console.log(unicode"退款后，jack的余额 = ", addrJack.balance);
        assert(addrJack.balance == jackBalanceBefore);

        // 项目的钱，清空了。
        console.log(unicode"退款后，项目的余额 = ", address(project).balance);
        assert(address(project).balance == 0);
    }
}
