// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Freelance Platform
 * @dev A complete gig economy platform on blockchain
 * @author Blockchain Developer
 */
contract Project {
    
    // State variables
    address public owner;
    uint256 public platformFeePercent = 25; // 2.5% platform fee (25/1000)
    uint256 public projectCounter;
    uint256 public userCounter;
    
    // Enums
    enum ProjectStatus { Open, InProgress, Completed, Disputed, Cancelled }
    enum UserType { Client, Freelancer, Both }
    
    // Structs
    struct User {
        uint256 userId;
        address userAddress;
        string name;
        string email;
        string skills;
        UserType userType;
        uint256 completedProjects;
        uint256 totalEarnings;
        uint256 rating; // Out of 5, multiplied by 100 (e.g., 450 = 4.5 stars)
        bool isActive;
    }
    
    struct ProjectInfo {
        uint256 projectId;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 budget;
        uint256 deadline;
        ProjectStatus status;
        uint256 createdAt;
        uint256 completedAt;
        bool clientApproval;
        bool freelancerDelivered;
    }
    
    struct Proposal {
        address freelancer;
        uint256 bidAmount;
        string coverLetter;
        uint256 proposedDeadline;
        uint256 submittedAt;
    }
    
    // Mappings
    mapping(address => User) public users;
    mapping(uint256 => ProjectInfo) public projects;
    mapping(uint256 => Proposal[]) public projectProposals;
    mapping(uint256 => mapping(address => bool)) public hasProposed;
    mapping(address => uint256[]) public userProjects; // Projects created by user
    mapping(address => uint256[]) public freelancerProjects; // Projects assigned to freelancer
    
    // Events
    event UserRegistered(address indexed user, string name, UserType userType);
    event ProjectCreated(uint256 indexed projectId, address indexed client, string title, uint256 budget);
    event ProposalSubmitted(uint256 indexed projectId, address indexed freelancer, uint256 bidAmount);
    event FreelancerHired(uint256 indexed projectId, address indexed freelancer, uint256 agreedAmount);
    event ProjectCompleted(uint256 indexed projectId, address indexed freelancer, uint256 payout);
    event PaymentReleased(uint256 indexed projectId, address indexed freelancer, uint256 amount);
    event ProjectCancelled(uint256 indexed projectId, string reason);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyRegistered() {
        require(users[msg.sender].isActive, "User must be registered");
        _;
    }
    
    modifier validProject(uint256 _projectId) {
        require(_projectId <= projectCounter && _projectId > 0, "Invalid project ID");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        projectCounter = 0;
        userCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create and manage freelance projects
     * @param _title Project title
     * @param _description Detailed project description
     * @param _deadline Project deadline (timestamp)
     */
    function createProject(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable onlyRegistered {
        require(msg.value > 0, "Project budget must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(
            users[msg.sender].userType == UserType.Client || 
            users[msg.sender].userType == UserType.Both, 
            "Only clients can create projects"
        );
        
        projectCounter++;
        
        projects[projectCounter] = ProjectInfo({
            projectId: projectCounter,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            status: ProjectStatus.Open,
            createdAt: block.timestamp,
            completedAt: 0,
            clientApproval: false,
            freelancerDelivered: false
        });
        
        userProjects[msg.sender].push(projectCounter);
        
        emit ProjectCreated(projectCounter, msg.sender, _title, msg.value);
    }
    
    /**
     * @dev Core Function 2: Handle proposals and freelancer hiring
     * @param _projectId ID of the project to bid on
     * @param _bidAmount Proposed amount for the project
     * @param _coverLetter Freelancer's proposal cover letter
     * @param _proposedDeadline Freelancer's proposed completion time
     */
    function submitProposal(
        uint256 _projectId,
        uint256 _bidAmount,
        string memory _coverLetter,
        uint256 _proposedDeadline
    ) external validProject(_projectId) onlyRegistered {
        ProjectInfo storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.Open, "Project is not accepting proposals");
        require(msg.sender != project.client, "Client cannot bid on own project");
        require(!hasProposed[_projectId][msg.sender], "Already submitted proposal for this project");
        require(
            users[msg.sender].userType == UserType.Freelancer || 
            users[msg.sender].userType == UserType.Both, 
            "Only freelancers can submit proposals"
        );
        require(_bidAmount > 0, "Bid amount must be greater than 0");
        require(_proposedDeadline > block.timestamp, "Proposed deadline must be in the future");
        
        projectProposals[_projectId].push(Proposal({
            freelancer: msg.sender,
            bidAmount: _bidAmount,
            coverLetter: _coverLetter,
            proposedDeadline: _proposedDeadline,
            submittedAt: block.timestamp
        }));
        
        hasProposed[_projectId][msg.sender] = true;
        
        emit ProposalSubmitted(_projectId, msg.sender, _bidAmount);
    }
    
    /**
     * @dev Hire a freelancer for the project
     * @param _projectId ID of the project
     * @param _freelancer Address of the chosen freelancer
     */
    function hireFreelancer(uint256 _projectId, address _freelancer) 
        external 
        validProject(_projectId) 
        onlyRegistered 
    {
        ProjectInfo storage project = projects[_projectId];
        
        require(msg.sender == project.client, "Only project client can hire freelancer");
        require(project.status == ProjectStatus.Open, "Project is not open for hiring");
        require(hasProposed[_projectId][_freelancer], "Freelancer has not submitted proposal");
        
        // Find the freelancer's proposal
        Proposal[] storage proposals = projectProposals[_projectId];
        uint256 agreedAmount = 0;
        
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].freelancer == _freelancer) {
                agreedAmount = proposals[i].bidAmount;
                project.deadline = proposals[i].proposedDeadline;
                break;
            }
        }
        
        require(agreedAmount > 0, "Freelancer proposal not found");
        
        // Calculate refund amount (difference between budget and agreed amount)
        if (project.budget > agreedAmount) {
            uint256 refundAmount = project.budget - agreedAmount;
            payable(project.client).transfer(refundAmount);
            project.budget = agreedAmount;
        }
        
        project.freelancer = _freelancer;
        project.status = ProjectStatus.InProgress;
        freelancerProjects[_freelancer].push(_projectId);
        
        emit FreelancerHired(_projectId, _freelancer, agreedAmount);
    }
    
    /**
     * @dev Core Function 3: Complete project and handle payments
     * @param _projectId ID of the project to complete
     */
    function completeProject(uint256 _projectId) 
        external 
        validProject(_projectId) 
        onlyRegistered 
    {
        ProjectInfo storage project = projects[_projectId];
        
        require(project.status == ProjectStatus.InProgress, "Project is not in progress");
        
        if (msg.sender == project.freelancer) {
            project.freelancerDelivered = true;
        } else if (msg.sender == project.client) {
            project.clientApproval = true;
        } else {
            revert("Only client or freelancer can complete project");
        }
        
        // If both parties confirm completion, release payment
        if (project.freelancerDelivered && project.clientApproval) {
            project.status = ProjectStatus.Completed;
            project.completedAt = block.timestamp;
            
            // Calculate platform fee and freelancer payment
            uint256 platformFee = (project.budget * platformFeePercent) / 1000;
            uint256 freelancerPayment = project.budget - platformFee;
            
            // Transfer payments
            payable(project.freelancer).transfer(freelancerPayment);
            payable(owner).transfer(platformFee);
            
            // Update user statistics
            users[project.client].completedProjects++;
            users[project.freelancer].completedProjects++;
            users[project.freelancer].totalEarnings += freelancerPayment;
            
            emit ProjectCompleted(_projectId, project.freelancer, freelancerPayment);
            emit PaymentReleased(_projectId, project.freelancer, freelancerPayment);
        }
    }
    
    // Helper Functions
    
    /**
     * @dev Register a new user on the platform
     * @param _name User's full name
     * @param _email User's email address
     * @param _skills User's skills (comma-separated)
     * @param _userType Type of user (Client, Freelancer, or Both)
     */
    function registerUser(
        string memory _name,
        string memory _email,
        string memory _skills,
        UserType _userType
    ) external {
        require(!users[msg.sender].isActive, "User already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_email).length > 0, "Email cannot be empty");
        
        userCounter++;
        
        users[msg.sender] = User({
            userId: userCounter,
            userAddress: msg.sender,
            name: _name,
            email: _email,
            skills: _skills,
            userType: _userType,
            completedProjects: 0,
            totalEarnings: 0,
            rating: 500, // Default 5.0 rating
            isActive: true
        });
        
        emit UserRegistered(msg.sender, _name, _userType);
    }
    
    /**
     * @dev Cancel a project (only by client or in dispute cases)
     * @param _projectId ID of the project to cancel
     * @param _reason Reason for cancellation
     */
    function cancelProject(uint256 _projectId, string memory _reason) 
        external 
        validProject(_projectId) 
        onlyRegistered 
    {
        ProjectInfo storage project = projects[_projectId];
        
        require(
            msg.sender == project.client || msg.sender == owner,
            "Only client or platform owner can cancel project"
        );
        require(
            project.status == ProjectStatus.Open || project.status == ProjectStatus.InProgress,
            "Cannot cancel completed project"
        );
        
        project.status = ProjectStatus.Cancelled;
        
        // Refund the budget to client
        payable(project.client).transfer(project.budget);
        
        emit ProjectCancelled(_projectId, _reason);
    }
    
    // View Functions
    
    /**
     * @dev Get project proposals
     * @param _projectId ID of the project
     * @return Array of proposals
     */
    function getProjectProposals(uint256 _projectId) 
        external 
        view 
        validProject(_projectId) 
        returns (Proposal[] memory) 
    {
        return projectProposals[_projectId];
    }
    
    /**
     * @dev Get user's created projects
     * @param _user Address of the user
     * @return Array of project IDs
     */
    function getUserProjects(address _user) external view returns (uint256[] memory) {
        return userProjects[_user];
    }
    
    /**
     * @dev Get freelancer's assigned projects
     * @param _freelancer Address of the freelancer
     * @return Array of project IDs
     */
    function getFreelancerProjects(address _freelancer) external view returns (uint256[] memory) {
        return freelancerProjects[_freelancer];
    }
    
    // Admin Functions
    
    /**
     * @dev Update platform fee percentage (only owner)
     * @param _newFeePercent New fee percentage (out of 1000, e.g., 25 = 2.5%)
     */
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 100, "Platform fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
    
    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    /**
     * @dev Get contract balance
     * @return Current contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
