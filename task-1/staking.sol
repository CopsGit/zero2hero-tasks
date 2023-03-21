contract Staking {
    // 质押奖励的发放速率
    uint256 private rewardRate = 0;

    // 每次有用户操作时，更新为当前时间
    uint256 private lastUpdateTime;

    // 我们前面说到的每单位数量获得奖励的累加值，这里是乘上奖励发放速率后的值
    uint256 private rewardPerTokenStored;

    // 在单个用户维度上，为每个用户记录每次操作的累加值，同样也是乘上奖励发放速率后的值
    mapping(address => uint256) private userRewardPerTokenPaid;

    // 用户到当前时刻可领取的奖励数量
    mapping(address => uint256) public rewards;

    // 池子中质押总量
    uint256 private _totalSupply;

    // 用户的余额
    mapping(address => uint256) private _balances;

    // 更新奖励相关参数
    function updateRewardParams(address account) internal {
        // 更新累加值
        rewardPerTokenStored = rewardPerToken();
        // 更新最新有效时间戳
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            // 计算用户的奖励数量
            uint256 earnedReward = earned(account);
            if (earnedReward > 0) {
                // 更新奖励数量
                rewards[account] = rewards[account].add(earnedReward);
                // 更新用户的累加值
                userRewardPerTokenPaid[account] = rewardPerTokenStored;
            }
        }
    }

    function stake(uint256 amount) external nonReentrant notPaused {
        require(amount > 0, "Cannot stake 0");
        // 转移代币
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        // 更新奖励参数
        updateRewardParams(msg.sender);
        // 更新池子信息
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        // 更新奖励参数
        updateRewardParams(msg.sender);
        // 更新池子信息
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        // 转移代币
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // 计算当前时刻的累加值
    function rewardPerToken() public view returns (uint256) {
        // 如果池子里的数量为0，说明上一个区间内没有必要发放奖励，因此累加值不变
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        // 计算累加值，上一个累加值加上最近一个区间的单位数量可获得的奖励数量
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    // 获取当前有效时间，如果活动结束了，就用结束时间，否则就用当前时间
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    // 计算用户可以领取的奖励数量
    // 质押数量 * （当前累加值 - 用户上次操作时的累加值）+ 上次更新的奖励数量
    function earned(address account) public view returns (uint256) {
        require(account != address(0), "Invalid account address");
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).add(rewards[account]).div(1e18);
    }

    modifier updateReward(address account) {
        // 更新奖励参数
        updateRewardParams(account);
        _;
    }

    // 允许管理员更新奖励速率
    function setRewardRate(uint256 rate) external onlyOwner {
        require(rate >= 0, "Invalid reward rate");
        updateRewardParams(address(0));
        rewardRate = rate;
        emit RewardRateUpdated(rate);
    }

    // 允许用户领取奖励
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // 允许用户提取所有代币和奖励
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }
}