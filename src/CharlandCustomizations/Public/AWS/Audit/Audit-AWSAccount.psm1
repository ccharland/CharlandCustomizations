<#
.SYNOPSIS
AWS Account Audit PowerShell Module

.DESCRIPTION
This module provides a collection of PowerShell functions for auditing AWS accounts and resources.
It includes functions for analyzing EC2 instances, security groups, IAM resources, S3 buckets,
and other AWS services without working with CloudFormation templates.

.NOTES
Author: Generated from aws-templates-tools-snippets repository
Version: 1.0
Created: August 2025

This module excludes CloudFormation template processing functions which are available
in the TemplateProcessing.psm1 module.
#>

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"

# ================================================================================================
# Get-CCEC2SGInUse Function
# ================================================================================================

<#
.SYNOPSIS
    Shows the resources associated with each EC2 Security Group in a region.
.DESCRIPTION
    Shows EC2 Security group and its associated resources. This includes: Instances, Network Interfaces, Load Balancers, Endpoints, Databases, Client Endpoints, Lambda Functions, ElastiCache Clusters, MSK Clusters, OpenSearch Domains, Redshift Clusters, EMR Clusters, DocumentDB Clusters, Neptune Clusters, MQ Brokers, FSx File Systems, Directories, WorkSpaces and SageMaker Notebooks.
    The script will return a list of security groups and the resources associated with them. It will also show the number of resources associated with each security group.

.PARAMETER Region
        The AWS region to use. If not specified, the default region will be used.
.PARAMETER GroupId
        The security group ID to check. If not specified, all security groups in the region will be checked.
.PARAMETER ProfileName
        The AWS credential profile name to use.
.PARAMETER AccessKey
        The AWS access key for authentication.
.PARAMETER SecretKey
        The AWS secret key for authentication.
.PARAMETER SessionToken
        The AWS session token for temporary credentials.
.PARAMETER Credential
        An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
        The location of the credentials file to use.
.PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
.INPUTS
    Amazon.EC2.Model.SecurityGroup
        Used to specify the security group ID. This is the ID of the security group to check for associated resources.

.NOTES
    Not all types have been tested

.OUTPUTS
AWS.EC2.SecurityGroupUsage

    The output will be in the form of a PowerShell object with the following properties:
        SecurityGroupId
        SecurityGroupName
        UsedByCount
        AssociatedInstances
        AssociatedNetworkInterfaces
        AssociatedLoadBalancers
        AssociatedEndpoints
        AssociatedDatabases
        AssociatedClientEndpoints
        AssociatedLambdaFunctions
        AssociatedElastiCacheClusters
        AssociatedMSKClusters
        AssociatedOpenSearchDomains
        AssociatedRedshiftClusters
        AssociatedEMRClusters
        AssociatedDocumentDBClusters
        AssociatedNeptuneClusters
        AssociatedMQBrokers
        AssociatedFSxFileSystems
        AssociatedDirectories
        AssociatedWorkSpaces
        AssociatedSageMakerNotebooks

    Example Output:
SecurityGroupId                : sg-12345678
SecurityGroupName              : my-security-group
UsedByCount                    : 3
AssociatedInstances            : i-12345678, i-87654321
AssociatedNetworkInterfaces    : eni-12345678
AssociatedLoadBalancers        : my-load-balancer
AssociatedEndpoints            :
AssociatedDatabases            :
AssociatedClientEndpoints      :
AssociatedLambdaFunctions      :
AssociatedElastiCacheClusters  :
AssociatedMSKClusters          :
AssociatedOpenSearchDomains    :
AssociatedRedshiftClusters     :
AssociatedEMRClusters          :
AssociatedDocumentDBClusters   :
AssociatedNeptuneClusters      :
AssociatedMQBrokers            :
AssociatedFSxFileSystems       :
AssociatedDirectories          :
AssociatedWorkSpaces           :
AssociatedSageMakerNotebooks   :

.EXAMPLE
    Get-CCEC2SGInUse
    # Gets all security groups in the default region and shows their associated resources.

.EXAMPLE
    Get-CCEC2SGInUse -Region us-west-2
    # Gets all security groups in the us-west-2 region and shows their associated resources.

.EXAMPLE
    Get-CCEC2SGInUse -GroupId sg-12345678
    # Gets the security group with the ID sg-12345678 and shows its associated resources.

.EXAMPLE
    Get-EC2SecurityGroup -GroupId sg-12345678 | Get-CCEC2SGInUse
    # Gets the security group with the ID sg-12345678 using the pipeline and shows its associated resources.

#>
function Get-CCEC2SGInUse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$GroupId = @(),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )
    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        try {
            if ($GroupId.Count -eq 0) {
                Write-Verbose "No security groups specified. Getting all security groups in the specified region"
                Write-Progress -Activity 'Get Security Group List:' -Status 'In Progress'
                $GroupId = (Get-EC2SecurityGroup @awsParams).GroupId
                if ($GroupId.Count -eq 0) {
                    throw "No security groups found in the specified region"
                }
            }
        }
        catch {
            throw "No security groups found in the specified region"
        }
        finally {
            Write-Progress -Activity 'Get Security Group List:' -Completed
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Instances'
        try {
            $InstancesMaster = Get-EC2Instance @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2Instance: Command not found, skipping"
            $InstancesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2Instance: Insufficient permissions, skipping"
                $InstancesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'NetworkInterfaces'
        try {
            $NetworkInterfaceMaster = Get-EC2NetworkInterface @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2NetworkInterface: Command not found, skipping"
            $NetworkInterfaceMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2NetworkInterface: Insufficient permissions, skipping"
                $NetworkInterfaceMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'LoadBalancer'
        try {
            $LoadBalancerMaster = Get-ELB2LoadBalancer @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ELB2LoadBalancer: Command not found, skipping"
            $LoadBalancerMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ELB2LoadBalancer: Insufficient permissions, skipping"
                $LoadBalancerMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EndPoints'
        try {
            $EndPointsMaster = Get-EC2VPCEndpoint @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2VPCEndpoint: Command not found, skipping"
            $EndPointsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2VPCEndpoint: Insufficient permissions, skipping"
                $EndPointsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Databases'
        try {
            $DatabasesMaster = Get-RDSDBInstance @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-RDSDBInstance: Command not found, skipping"
            $DatabasesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-RDSDBInstance: Insufficient permissions, skipping"
                $DatabasesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ClientEndpoints'
        try {
            $VPNCLientEndpointMaster = Get-EC2ClientVpnEndpoint @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2ClientVpnEndpoint: Command not found, skipping"
            $VPNCLientEndpointMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2ClientVpnEndpoint: Insufficient permissions, skipping"
                $VPNCLientEndpointMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Lambda'
        try {
            $LambdaFunctionsMaster = Get-LMFunctionList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-LMFunctionList: Command not found, skipping"
            $LambdaFunctionsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-LMFunctionList: Insufficient permissions, skipping"
                $LambdaFunctionsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ElasticCache'
        try {
            $ElastiCacheClustersMaster = Get-ECCacheCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ECCacheCluster: Command not found, skipping"
            $ElastiCacheClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ECCacheCluster: Insufficient permissions, skipping"
                $ElastiCacheClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'MSK'
        try {
            $MSKClustersMaster = Get-MSKClusterList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-MSKClusterList: Command not found, skipping"
            $MSKClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-MSKClusterList: Insufficient permissions, skipping"
                $MSKClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Neptune'
        try {
            $NeptuneClustersMaster = Get-NPTDBCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-NPTDBCluster: Command not found, skipping"
            $NeptuneClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-NPTDBCluster: Insufficient permissions, skipping"
                $NeptuneClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'MQBroker'
        try {
            $MQBrokersMaster = Get-MQBrokerList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-MQBrokerList: Command not found, skipping"
            $MQBrokersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-MQBrokerList: Insufficient permissions, skipping"
                $MQBrokersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'FSX'
        try {
            $FSxFileSystemsMaster = Get-FSXFileSystem @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-FSXFileSystem: Command not found, skipping"
            $FSxFileSystemsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-FSXFileSystem: Insufficient permissions, skipping"
                $FSxFileSystemsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Directory'
        try {
            $DirectoriesMaster = Get-DSDirectory @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DSDirectory: Command not found, skipping"
            $DirectoriesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DSDirectory: Insufficient permissions, skipping"
                $DirectoriesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Workspace'
        try {
            $WorkSpacesMaster = Get-WKSWorkspace @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-WKSWorkspace: Command not found, skipping"
            $WorkSpacesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-WKSWorkspace: Insufficient permissions, skipping"
                $WorkSpacesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'SageMaker'

        try {
            $SageMakerNotebookInstanceListMaster = Get-SMNotebookInstanceList @awsParams | ForEach-Object { Get-SMNotebookInstance @awsParams }
        }
        catch {
            $SageMakerNotebookInstanceListMaster = $null
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'OpenSearch'
        try {
            $OpenSearchDomainsMaster = Get-OSDomainNameList @awsParams | ForEach-Object {
                Get-OSDomainConfig -DomainName $_.DomainName @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-OSDomainNameList: Command not found, skipping"
            $OpenSearchDomainsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-OSDomainNameList: Insufficient permissions, skipping"
                $OpenSearchDomainsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Redshift'
        try {
            $RedshiftClustersMaster = Get-RSCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-RSCluster: Command not found, skipping"
            $RedshiftClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-RSCluster: Insufficient permissions, skipping"
                $RedshiftClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EMR'
        try {
            $EMRClustersMaster = Get-EMRClusterList @awsParams | Where-Object {
                $_.Status.State -notin @('TERMINATED', 'TERMINATED_WITH_ERRORS')
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EMRClusterList: Command not found, skipping"
            $EMRClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EMRClusterList: Insufficient permissions, skipping"
                $EMRClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'DocumentDB'
        try {
            $DocumentDBClustersMaster = Get-DOCDBCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DOCDBCluster: Command not found, skipping"
            $DocumentDBClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DOCDBCluster: Insufficient permissions, skipping"
                $DocumentDBClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ECS'
        try {
            $ECSServicesMaster = @()
            $clusterArns = Get-ECSClusterList @awsParams
            foreach ($clusterArn in $clusterArns) {
                $serviceArns = Get-ECSClusterService -Cluster $clusterArn @awsParams
                if ($serviceArns) {
                    $ECSServicesMaster += Get-ECSService -Cluster $clusterArn -Service $serviceArns @awsParams
                }
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ECSClusterList: Command not found, skipping"
            $ECSServicesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ECSClusterList: Insufficient permissions, skipping"
                $ECSServicesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EFS'
        try {
            $EFSMountTargetsMaster = @()
            $fileSystems = Get-EFSFileSystem @awsParams
            foreach ($fs in $fileSystems) {
                $EFSMountTargetsMaster += Get-EFSMountTarget -FileSystemId $fs.FileSystemId @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EFSFileSystem: Command not found, skipping"
            $EFSMountTargetsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EFSFileSystem: Insufficient permissions, skipping"
                $EFSMountTargetsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'CodeBuild'
        try {
            $CodeBuildProjectsMaster = @()
            $projectNames = Get-CBProjectList @awsParams
            if ($projectNames) {
                $CodeBuildProjectsMaster = Get-CBBatchProject -Name $projectNames @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-CBProjectList: Command not found, skipping"
            $CodeBuildProjectsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-CBProjectList: Insufficient permissions, skipping"
                $CodeBuildProjectsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'DAX'
        try {
            $DAXClustersMaster = Get-DAXCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DAXCluster: Command not found, skipping"
            $DAXClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DAXCluster: Insufficient permissions, skipping"
                $DAXClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'TransferFamily'
        try {
            $TransferServersMaster = Get-TFRServerList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-TFRServerList: Command not found, skipping"
            $TransferServersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-TFRServerList: Insufficient permissions, skipping"
                $TransferServersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Glue'
        try {
            $GlueConnectionsMaster = Get-GLUEConnectionList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-GLUEConnectionList: Command not found, skipping"
            $GlueConnectionsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-GLUEConnectionList: Insufficient permissions, skipping"
                $GlueConnectionsMaster = @()
            }
            else { throw }
        }

        # Initialize an array to store results
        $Results = @()
        # start progress display
        $Total = $GroupId.Count
        $Count = 0
        Write-Progress -Activity 'Get Resource List:' -Completed
    }

    process {
        foreach ($SG in $GroupId) {
            $SecurityGroup = Get-EC2SecurityGroup @awsParams -GroupId $SG
            $Count++
            Write-Verbose "Count: $count"
            Write-Verbose "Total: $Total"
            Write-Progress -Activity "Processing SG: $SG" -Status 'Progress:' -PercentComplete ($Count / $Total * 100)
            $UsedByCount = 0
            $Instances = $InstancesMaster | Where-Object {
                $_.Instances.SecurityGroups.GroupId -contains $SG
            }

            $UsedByCount += $Instances.Count
            $NetworkInterface = $NetworkInterfaceMaster | Where-Object {
                $_.Groups.GroupId -contains $SG
            }
            $UsedByCount += $NetworkInterface.Count
            # Get associated Load Balancers
            $LoadBalancers = $LoadBalancerMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $LoadBalancers.Count

            $Endpoints = $EndpointsMaster | Where-Object {
                $_.Groups.GroupId -contains $SG
            }
            $UsedByCount += $Endpoints.Count
            $Databases = $DatabasesMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $Databases.Count
            $VPNClientEndpoints = $VPNCLientEndpointMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $VPNClientEndpoints.Count

            # Get associated Lambda functions in VPC
            $LambdaFunctions = $LambdaFunctionsMaster | Where-Object {
                $null -ne $_.VpcConfig -and $_.VpcConfig.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $LambdaFunctions.Count

            # Get associated ElastiCache clusters
            $ElastiCacheClusters = $ElastiCacheClustersMaster | Where-Object {
                $_.SecurityGroups.SecurityGroupId -contains $SG
            }
            $UsedByCount += $ElastiCacheClusters.Count

            # Get associated Amazon MSK clusters
            $MSKClusters = $MSKClustersMaster | ForEach-Object {
                $ClusterInfo = Get-MSKCluster -ClusterArn $_.ClusterArn @awsParams
                if ($ClusterInfo.BrokerNodeGroupInfo.SecurityGroups -contains $SG) {
                    $_
                }
            }
            $UsedByCount += $MSKClusters.Count

            # Get associated Neptune clusters
            $NeptuneClusters = $NeptuneClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $NeptuneClusters.Count
            # Get associated Amazon MQ brokers
            $MQBrokers = $MQBrokersMaster | ForEach-Object { Get-MQBroker @awsParams | Where-Object {
                    $_.SecurityGroups -contains $SG }
            }
            $UsedByCount += $MQBrokers.Count

            # Get associated FSx file systems
            $FSxFileSystems = $FSxFileSystemsMaster | Where-Object {
                $_.NetworkInterfaceIds | ForEach-Object {
                    $ENI = Get-EC2NetworkInterface -NetworkInterfaceId $_ @awsParams
                    $ENI.Groups.GroupId -contains $SG
                }
            }
            $UsedByCount += $FSxFileSystems.Count
            # Get associated Directory Service directories
            $Directories = $DirectoriesMaster | Where-Object {
                $_.VpcSettings.SecurityGroupId -eq $SG
            }
            $UsedByCount += $Directories.Count

            # Get associated WorkSpaces
            $WorkSpaces = $WorkSpacesMaster | ForEach-Object {
                $WorkspaceId = $_.WorkspaceId
                $WorkspaceDetails = Get-WKSWorkspace -WorkspaceId $WorkspaceId @awsParams
                if ($WorkspaceDetails.SecurityGroupIds -contains $SG) {
                    $_
                }
            }
            $UsedByCount += $WorkSpaces.Count

            if ($SageMakerNotebookInstanceListMaster.count) {
                $SageMakerNotebooks = $SageMakerNotebookInstanceListMaster | Where-Object {
                    $_.SecurityGroups -contains $SG }
            }
            else {
                $SageMakerNotebooks = @()
            }
            $UsedByCount += $SageMakerNotebooks.Count

            # Get associated OpenSearch domains
            $OpenSearchDomains = $OpenSearchDomainsMaster | Where-Object {
                $_.VPCOptions.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $OpenSearchDomains.Count

            # Get associated Redshift clusters
            $RedshiftClusters = $RedshiftClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $RedshiftClusters.Count

            # Get associated EMR clusters
            $EMRClusters = @()
            foreach ($emrCluster in $EMRClustersMaster) {
                try {
                    $emrDetail = Get-EMRCluster -ClusterId $emrCluster.Id @awsParams
                    if ($emrDetail.Ec2InstanceAttributes.EmrManagedMasterSecurityGroup -eq $SG -or
                        $emrDetail.Ec2InstanceAttributes.EmrManagedSlaveSecurityGroup -eq $SG -or
                        $emrDetail.Ec2InstanceAttributes.AdditionalMasterSecurityGroups -contains $SG -or
                        $emrDetail.Ec2InstanceAttributes.AdditionalSlaveSecurityGroups -contains $SG) {
                        $EMRClusters += $emrCluster
                    }
                }
                catch {
                    Write-Verbose "Get-EMRCluster ($($emrCluster.Id)): $_"
                }
            }
            $UsedByCount += $EMRClusters.Count

            # Get associated DocumentDB clusters
            $DocumentDBClusters = $DocumentDBClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $DocumentDBClusters.Count

            # Get associated ECS services (awsvpc mode)
            $ECSServices = $ECSServicesMaster | Where-Object {
                $_.NetworkConfiguration.AwsvpcConfiguration.SecurityGroups -contains $SG
            }
            $UsedByCount += $ECSServices.Count

            # Get associated EFS mount targets
            $EFSMountTargets = $EFSMountTargetsMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $EFSMountTargets.Count

            # Get associated CodeBuild projects
            $CodeBuildProjects = $CodeBuildProjectsMaster | Where-Object {
                $_.VpcConfig.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $CodeBuildProjects.Count

            # Get associated DAX clusters
            $DAXClusters = $DAXClustersMaster | Where-Object {
                $_.SecurityGroups.SecurityGroupIdentifier -contains $SG
            }
            $UsedByCount += $DAXClusters.Count

            # Get associated Transfer Family servers
            $TransferServers = $TransferServersMaster | Where-Object {
                $_.StructuredLogDestinations -contains $SG -or $_.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $TransferServers.Count

            # Get associated Glue connections
            $GlueConnections = $GlueConnectionsMaster | Where-Object {
                $_.PhysicalConnectionRequirements.SecurityGroupIdList -contains $SG
            }
            $UsedByCount += $GlueConnections.Count

            # Add results to the array
            $Results += [PSCustomObject]@{
                PSTypeName                    = 'AWS.EC2.SecurityGroupUsage'
                SecurityGroupId               = $SG
                SecurityGroupName             = $SecurityGroup.GroupName
                SecurityGroupDescription      = $SecurityGroup.Description
                UsedByCount                   = $UsedByCount
                AssociatedInstances           = $Instances.Instances.InstanceId -join ', '
                NetworkInterface              = $NetworkInterface.NetworkInterfaceId -join ', '
                AssociatedLoadBalancers       = $LoadBalancers.LoadBalancerName -join ', '
                AssociatedEndpoints           = $Endpoints.VpcEndpointId -join ', '
                AssociatedDatabases           = $Databases.DBInstanceIdentifier -join ', '
                AssociatedVPNClientEndpoints  = $VPNClientEndpoints.VpnClientConnectionId -join ', '
                AssociatedLambdaFunctions     = $LambdaFunctions.FunctionName -join ', '
                AssociatedElastiCacheClusters = $ElastiCacheClusters.CacheClusterId -join ', '
                AssociatedMSKClusters         = $MSKClusters.ClusterName -join ', '
                AssociatedOpenSearchDomains   = $OpenSearchDomains.DomainName -join ', '
                AssociatedRedshiftClusters    = $RedshiftClusters.ClusterIdentifier -join ', '
                AssociatedEMRClusters         = $EMRClusters.Id -join ', '
                AssociatedDocumentDBClusters  = $DocumentDBClusters.DBClusterIdentifier -join ', '
                AssociatedNeptuneClusters     = $NeptuneClusters.DBClusterIdentifier -join ', '
                AssociatedMQBrokers           = $MQBrokers.BrokerId -join ', '
                AssociatedFSxFileSystems      = $FSxFileSystems.FileSystemId -join ', '
                AssociatedDirectories         = $Directories.DirectoryId -join ', '
                AssociatedWorkSpaces          = $WorkSpaces.WorkspaceId -join ', '
                AssociatedSageMakerNotebooks  = $SageMakerNotebooks.NotebookInstanceName -join ', '
                AssociatedECSServices         = $ECSServices.ServiceName -join ', '
                AssociatedEFSMountTargets     = $EFSMountTargets.MountTargetId -join ', '
                AssociatedCodeBuildProjects   = $CodeBuildProjects.Name -join ', '
                AssociatedDAXClusters         = $DAXClusters.ClusterName -join ', '
                AssociatedTransferServers     = $TransferServers.ServerId -join ', '
                AssociatedGlueConnections     = $GlueConnections.Name -join ', '
            }
        }
    }

    end {
        return $Results
    }
}

# ================================================================================================
# Out-CCAWSSupportingInfo Function
# ================================================================================================

function Out-CCAWSSupportingInfo {
    <#
    .SYNOPSIS
        Exports AWS account supporting information to text files.
    .DESCRIPTION
        Retrieves and exports SSM parameters, Secrets Manager secret names, and
        CloudFormation exports for documentation or migration purposes.
    .PARAMETER Region
        AWS region to query. Defaults to current default region.
    .PARAMETER RootPath
        Root directory for output files. Defaults to current directory.
    .PARAMETER ProfileName
        AWS credential profile name.
    .PARAMETER AccessKey
        The AWS access key for authentication.
    .PARAMETER SecretKey
        The AWS secret key for authentication.
    .PARAMETER SessionToken
        The AWS session token for temporary credentials.
    .PARAMETER Credential
        An AWSCredentials object for authentication.
    .PARAMETER ProfileLocation
        The location of the credentials file to use.
    .PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
    .EXAMPLE
        Out-CCAWSSupportingInfo
    .EXAMPLE
        Out-CCAWSSupportingInfo -Region us-west-2 -RootPath C:\AWSInfo
    .OUTPUTS
        Creates files in <RootPath>/<AccountId>/<Region>/:
        - SSMParameters.txt
        - Secrets.txt (names only, not values)
        - CFNExports.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    $AccountId = (Get-STSCallerIdentity @awsParams).Account
    $RegionDisplay = if ($awsParams.ContainsKey('Region')) { $awsParams['Region'] } else { (Get-DefaultAWSRegion).Region }
    Write-Verbose "AccountId: $AccountId | Region: $RegionDisplay"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $RegionDisplay)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-SSMParameterList @awsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'SSMParameters.txt') -Force

    Get-SECSecretList @awsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'Secrets.txt') -Force

    Get-CFNExport @awsParams |
    Select-Object Name, Value |
    Out-File -FilePath (Join-Path $OutputDir 'CFNExports.txt') -Force

    Write-Output "Exported supporting info to: $OutputDir"
}

# ================================================================================================
# Out-CCAWSNetworkingComponent Function
# ================================================================================================

function Out-CCAWSNetworkingComponent {
    <#
    .SYNOPSIS
        Exports AWS VPC networking configuration to text files.
    .DESCRIPTION
        Retrieves and exports VPC networking configuration including VPN connections,
        VPCs, subnets, route tables, prefix lists, transit gateway route tables, and
        transit gateway attachments. Output is organized by account ID and region.
    .PARAMETER Region
        AWS region to query. Defaults to current default region.
    .PARAMETER RootPath
        Root directory for output files. Defaults to current directory.
    .PARAMETER ProfileName
        AWS credential profile name.
    .PARAMETER AccessKey
        The AWS access key for authentication.
    .PARAMETER SecretKey
        The AWS secret key for authentication.
    .PARAMETER SessionToken
        The AWS session token for temporary credentials.
    .PARAMETER Credential
        An AWSCredentials object for authentication.
    .PARAMETER ProfileLocation
        The location of the credentials file to use.
    .PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
    .EXAMPLE
        Out-CCAWSNetworkingComponent
    .EXAMPLE
        Out-CCAWSNetworkingComponent -Region us-east-1 -RootPath C:\AWS
    .OUTPUTS
        Creates files in <RootPath>/<AccountId>/<Region>/:
        - VPNConnections.txt
        - VPCs.txt
        - Subnets.txt
        - RouteTables.txt
        - PrefixLists.txt
        - TransitGatewayRouteTables.txt
        - TransitGatewayAttachments.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    $AccountId = (Get-STSCallerIdentity @awsParams).Account
    $RegionDisplay = if ($awsParams.ContainsKey('Region')) { $awsParams['Region'] } else { (Get-DefaultAWSRegion).Region }
    Write-Verbose "AccountId: $AccountId | Region: $RegionDisplay"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $RegionDisplay)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-EC2VpnConnection @awsParams |
    Select-Object VpnConnectionId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPNConnections.txt') -Force

    Get-EC2Vpc @awsParams |
    Select-Object VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock,
    @{Name = 'AssociatedCidrBlocks'; Expression = { ($_.CidrBlockAssociationSet | ForEach-Object { $_.CidrBlock }) -join ', ' } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPCs.txt') -Force

    Get-EC2Subnet @awsParams |
    Select-Object VpcId, SubnetId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock, AvailabilityZone, AvailableIpAddressCount |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'Subnets.txt') -Force

    Get-EC2RouteTable @awsParams |
    Select-Object RouteTableId, VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    @{Name = 'AssociationCount'; Expression = { ($_.Associations | Measure-Object).Count } } |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'RouteTables.txt') -Force

    Get-EC2ManagedPrefixList @awsParams |
    Format-Table PrefixListId, PrefixListName |
    Out-File -FilePath (Join-Path $OutputDir 'PrefixLists.txt') -Force

    Get-EC2TransitGatewayRouteTable @awsParams |
    Select-Object TransitGatewayRouteTableId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'TransitGatewayRouteTables.txt') -Force

    Get-EC2TransitGatewayAttachment @awsParams |
    Select-Object `
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    ResourceId,
    @{Name = 'AssociatedRT'; Expression = { ($_.Association | Where-Object { $_.State -eq 'associated' }).TransitGatewayRouteTableId } },
    TransitGatewayAttachmentId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'TransitGatewayAttachments.txt') -Force

    Write-Output "Exported networking components to: $OutputDir"
}

# ================================================================================================
# Get-CCIAMAuditList Function
# ================================================================================================

<#
.SYNOPSIS
    Consolidated IAM Credential report from multiple accounts into a single report.

.DESCRIPTION
    Invokes Get-IAMCredentialReport for each profile for multiple accounts, and outputs the result into a text array
    that is CSV formatted.

    For information on the report format, refer to the AWS Identity and Access Mangement User
    Guide section "Getting credentail reports."

.PARAMETER ProfileName
    List of AWS Profiles that have permissison to call:

    iam:GenerateCredentailReport
    iam:GetCredentialReport

.EXAMPLE
    PS> $profile-list= @(
        'Profile1',
        'Profile2'
    )

    PS> Get-CCIAMAuditList -ProfileName $profile-list  |out-file -Path '\reports\complete-credentails.csv'

.NOTES
    https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_getting-report.html?icmpid=docs_iam_help_panel#id_credentials_understanding_the_report_format
#>
function Get-CCIAMAuditList {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $ProfileName
    )

    begin {
        $allProfiles = @()
    }

    process {
        $allProfiles += $ProfileName
    }

    end {
        do {
            $RequestState = $allProfiles | ForEach-Object { Request-IAMCredentialReport -ProfileName $_ }
            Write-Verbose 'Waiting for report to generate'
            Start-Sleep -Seconds 5
        } while (($RequestState.State -notlike 'COMPLETE').count -ne 0)

        Write-Verbose 'Credential report complete'
        $SkipLines = 0
        $Results = foreach ($ProfileItem in $allProfiles) {
            Get-IAMCredentialReport -AsTextArray -ProfileName $ProfileItem | Select-Object -Skip $SkipLines
            $skiplines = 1
        }
        return $Results
    }
}

# ================================================================================================
# Get-CCGlobalAuditReportItem Function
# ================================================================================================

<#
.SYNOPSIS
    Create list of AWS resources in use.
.DESCRIPTION
    First version, just to get the basics in place. Provides a count of various AWS resources
    across specified regions.
.PARAMETER Region
    The AWS region(s) to audit. Defaults to us-east-1 if not specified.
.EXAMPLE
    PS C:\> Get-CCGlobalAuditReportItem
    Gets a count of AWS resources in the default region (us-east-1)
.EXAMPLE
    PS C:\> Get-CCGlobalAuditReportItem -Region @("us-east-1", "us-west-2")
    Gets a count of AWS resources in multiple regions
.INPUTS
    String array of region names
.OUTPUTS
    PSCustomObject with resource counts by region
.NOTES
    General notes - this is a first version to get the basics in place
#>
function Get-CCGlobalAuditReportItem {
    [CmdletBinding()]
    param(
        [string[]]$Region = @('us-east-1'),

        # AWS common parameters (Region excluded - handled by $Region array above)
        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    # Build base AWS params (excludes Region since we iterate over regions)
    $baseAwsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    $baseAwsParams.Remove('Region') | Out-Null

    $output = @()
    foreach ($RegionName in $Region) {
        $regionParams = $baseAwsParams.Clone()
        $regionParams['Region'] = $RegionName

        Write-Output $RegionName
        $RegionResults = New-Object -TypeName 'PSCustomObject' -Property @{
            account          = (Get-STSCallerIdentity @regionParams).Account
            region           = $RegionName
            VMCount          = (Get-Ec2Instance @regionParams).count
            CloudFront       = (Get-CFDistributionList @regionParams).count
            LoadBalancer     = (Get-ELB2LoadBalancer @regionParams).count + (Get-ELBLoadBalancer @regionParams).count
            AutoScaling      = (Get-ASAutoScalingGroup @regionParams).count
            RDS              = (Get-RDSDBInstance @regionParams).count
            EFS              = (Get-EFSFileSystem @regionParams).count
            ECS              = (Get-ECSClusterList @regionParams).count
            EKS              = (Get-EKSClusterList @regionParams).count
            KMS              = (Get-KMSKeyList @regionParams).count
            Lambda           = (Get-LMFunctionList @regionParams).count
            Certs            = (Get-ACMCertificateList @regionParams).count
            Secrets          = (Get-SECSecretList @regionParams).count
            DynamoDB         = (Get-DDBTableList @regionParams).count
            RDS_Maria        = (Get-RDSDBInstance @regionParams -filter @{name = 'engine'; values = 'mariadb' }).count
            Redshift         = (Get-RSCluster @regionParams).count
            SNS_SQS          = (Get-SQSQueue @regionParams).count + (Get-SNSTopic @regionParams).count
            Step             = (Get-SFNStateMachineList @regionParams).count
            DirectoryService = (Get-DSDirectory @regionParams).count
            Forecast         = (Get-FRCForecastList @regionParams).count
            StorageGateway   = (Get-SGGateway @regionParams).count
        }

        $output += $RegionResults
    }
    return $output
}

# ================================================================================================
# Get-CCEC2KeyTagNameStatus Function
# ================================================================================================

<#
.SYNOPSIS
 Tells you if a EC2 Key with tag name is on the listed resources.

.DESCRIPTION
 Good way of finding out if you're missing key items, like Name, Environment, for any EC2 object

.NOTES
 Provides some output that we can use.

.PARAMETER TagKey
 Tag key to search for, just a string.. Value is ignored (for now)

.PARAMETER taglist
 group object of tags, results of command:
  get-EC2Tag |group-object resourceid
  Must be in a group
  no error checking
  if null, will call above line to generate master list:

.PARAMETER filter
filter to pass to get-ec2tag

.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.OUTPUTS
PSobject
ResourceID, KeyPresent

.EXAMPLE
Get-CCEC2KeyTagNameStatus -TagKey "Name"
Checks if all EC2 resources have a "Name" tag
#>
function Get-CCEC2KeyTagNameStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]
        $TagKey,
        $taglist = $null,
        $filter = $null,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        if ($null -eq $taglist) {
            if ($filter) {
                $Taglist = Get-EC2Tag @awsParams -filter $filter | Group-Object resourceId
            }
            else {
                $Taglist = Get-EC2Tag @awsParams | Group-Object resourceId
            }
        }

        $output = @()

        foreach ($item in $taglist) {
            $result = New-Object -TypeName PSCustomObject
            $result | Add-Member -MemberType NoteProperty -Name 'ResourceId' -Value $item.name
            $result | Add-Member -MemberType NoteProperty -Name 'KeyName' -Value $TagKey

            foreach ($tag in $item.group) {
                if ($tag.key -eq $TagKey) {
                    break
                }
            }
            #process results
            if ($tag.key -eq $TagKey) {
                $result | Add-Member -MemberType NoteProperty -Name 'KeyPresent' -Value $True
            }
            else {
                $result | Add-Member -MemberType NoteProperty -Name 'KeyPresent' -Value $False
            }
            $output += $result
        }

        if ($output.count -ne $taglist.count) {
            throw 'Script error- Input item count does not match output item count'
        }
        return $output
    }
}

# ================================================================================================
# Get-CCEC2SnapshotReport Function
# ================================================================================================

<#
.SYNOPSIS
    Gets a listing of EC2 snapshots for a region.

.DESCRIPTION
    Calls Get-EC2Snapshot in a batch format to audit accounts with thousands of
    snapshots. Retrieves all self-owned snapshots using pagination and returns
    each snapshot's metadata along with any associated tags as dynamic properties.

.PARAMETER MaxResults
    Maximum number of snapshots to retrieve per API call. Defaults to 200.
    Lower values reduce memory usage per batch; higher values reduce API calls.

.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.OUTPUTS
    PSCustomObject with the following properties:
    - SnapshotId: The snapshot identifier
    - VolumeId: The source volume identifier
    - StartTime: When the snapshot was initiated
    - Description: Snapshot description
    - State: Current snapshot state (pending, completed, error)
    - Tag:<TagName>: One dynamic property per tag on the snapshot

.EXAMPLE
    PS> Get-CCEC2SnapshotReport
    Returns all self-owned snapshots in the current region with default batch size.

.EXAMPLE
    PS> Get-CCEC2SnapshotReport -MaxResults 500 | Export-Csv -Path snapshots.csv -NoTypeInformation
    Exports all snapshots to CSV using larger batch size for fewer API calls.

.EXAMPLE
    PS> Get-CCEC2SnapshotReport | Where-Object { $_.State -eq 'completed' } | Measure-Object
    Counts all completed snapshots in the current region.

.NOTES
    Uses $AWSHistory.LastServiceResponse.NextToken for pagination.
    The -OwnerId 'self' filter ensures only account-owned snapshots are returned.
#>
function Get-CCEC2SnapshotReport {
    [CmdletBinding()]
    param(
        [int]$MaxResults = 200,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        $output = @()
        $NextToken = $null

        do {
            #process in smaller groups
            Write-Information -MessageData "Fetching info on up to $($MaxResults) snapshots"
            $SnapshotList = Get-EC2Snapshot -OwnerId self -NextToken $NextToken -maxresult $MaxResults @awsParams
            $NextToken = $AWShistory.LastServiceResponse.NextToken
            $Message = 'Starting processing of ' + $SnapshotList.count + ' snapshots'
            Write-Information $Message

            foreach ($Snapshot in $SnapshotList) {
                $record = New-Object -TypeName PSCustomObject -Property ([ordered] @{
                        SnapshotId  = $Snapshot.SnapshotId
                        VolumeId    = $Snapshot.VolumeId
                        StartTime   = $Snapshot.StartTime
                        Description = $Snapshot.Description
                        State       = $Snapshot.State
                    })

                $Snapshot.Tags | Sort-Object Key | ForEach-Object {
                    Add-Member -InputObject $Record -NotePropertyName "Tag:$($_.key)" -NotePropertyValue $($_.value)
                }
                $output += $record
            }
            Write-Information "output size is $($output.count)"
        } while ($NextToken)
        return $output
    }
}

# ================================================================================================
# Get-CCEC2VolumeReport Function
# ================================================================================================

<#
.SYNOPSIS
    Gets a report of all EC2 volumes in the current region
.DESCRIPTION
    Lists all EC2 volumes and their attachment status, including unattached volumes
.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.
.EXAMPLE
    Get-CCEC2VolumeReport
    Gets all volumes in the current region
#>
function Get-CCEC2VolumeReport {
    [CmdletBinding()]
    param(
        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        $volist = Get-Ec2Volume @awsParams
        Write-Verbose "Number of volumes in region: $($volist.count) "
        $results = @()

        foreach ($item in $volist) {
            if ($item.state -eq 'available') {
                #instance not attached
                Write-Verbose "unattached volume $($item.volumeid)"
                $results += $item | Select-Object Volumeid, @{Name = 'InstanceID' ; Expression = { 'NoInstance' } }, Size, Iops, VolumeType
            }
            else {
                Write-Verbose "attached volume $($item.volumeid)"
                foreach ($attachment in $item.Attachments ) {
                    $results += $attachment | Select-Object VolumeId, InstanceId, @{Name = 'Size'; Expression = { $item.Size } },
                    @{Name = 'Iops'; Expression = { $item.Iops } }, @{Name = 'VolumeType'; Expression = { $item.VolumeType } }
                }
            }
        }
        return $results
    }
}

# ================================================================================================
# Start-CCEC2RetryLoop Function
# ================================================================================================

<#
.SYNOPSIS
    Implements a retry loop for EC2 operations
.DESCRIPTION
    Provides a retry mechanism for EC2 operations that might fail due to temporary issues
.PARAMETER ScriptBlock
    The script block to execute
.PARAMETER MaxRetries
    Maximum number of retries (default: 3)
.PARAMETER DelaySeconds
    Delay between retries in seconds (default: 5)
.EXAMPLE
    Start-CCEC2RetryLoop -ScriptBlock {Get-EC2Instance} -MaxRetries 5
#>
function Start-CCEC2RetryLoop {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5
    )

    if (-not $PSCmdlet.ShouldProcess("EC2 Operation", "Execute with retry (max $MaxRetries attempts)")) {
        return
    }

    $attempt = 0
    do {
        $attempt++
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            if ($attempt -lt $MaxRetries) {
                Write-Warning "Attempt $attempt failed: $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw "All $MaxRetries attempts failed. Last error: $($_.Exception.Message)"
            }
        }
    } while ($attempt -lt $MaxRetries)
}

# ================================================================================================
# Find-CCOpenSecurityGroup Function
# ================================================================================================

<#
.SYNOPSIS
    Finds EC2 security groups with overly permissive inbound rules (0.0.0.0/0) on ports other than 80 and 443.

.DESCRIPTION
    Scans all security groups in the current AWS region for inbound rules that allow traffic
    from 0.0.0.0/0 or ::/0 to any port other than 80 and 443. These rules represent potential
    security risks.

.PARAMETER Region
    AWS region to scan. Uses the current default region if not specified.

.PARAMETER ProfileName
    AWS credential profile to use.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.PARAMETER AllowedPorts
    Ports that are acceptable to have open to the internet. Defaults to 80 and 443.

.EXAMPLE
    Find-CCOpenSecurityGroup
    Scans the current region for overly permissive security groups.

.EXAMPLE
    Find-CCOpenSecurityGroup -Region us-west-2 -AllowedPorts 80,443,8080
    Scans us-west-2, treating ports 80, 443, and 8080 as acceptable.
#>
function Find-CCOpenSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int[]]$AllowedPorts = @(80, 443),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        try {
            Write-Verbose 'Retrieving security groups...'
            $securityGroups = Get-EC2SecurityGroup @awsParams

            if (-not $securityGroups) {
                Write-Verbose 'No security groups found.'
                Write-Output ([PSCustomObject]@{})
                return
            }

            Write-Verbose "Found $($securityGroups.Count) security groups. Checking inbound rules..."

            $findings = foreach ($sg in $securityGroups) {
                foreach ($rule in $sg.IpPermissions) {
                    # Check IPv4 ranges for 0.0.0.0/0
                    $openIpv4 = $rule.Ipv4Ranges | Where-Object { $_.CidrIp -eq '0.0.0.0/0' }
                    # Check IPv6 ranges for ::/0
                    $openIpv6 = $rule.Ipv6Ranges | Where-Object { $_.CidrIpv6 -eq '::/0' }

                    if ($openIpv4 -or $openIpv6) {
                        $fromPort = $rule.FromPort
                        $toPort = $rule.ToPort

                        # IpProtocol -1 means all traffic (all ports)
                        $isAllTraffic = $rule.IpProtocol -eq '-1'

                        # Check if the rule covers only allowed ports
                        $isAllowedOnly = (-not $isAllTraffic) -and
                        ($fromPort -eq $toPort) -and
                        ($fromPort -in $AllowedPorts)

                        if (-not $isAllowedOnly) {
                            # Determine which open CIDR triggered the finding
                            $openCidrs = @()
                            if ($openIpv4) { $openCidrs += '0.0.0.0/0' }
                            if ($openIpv6) { $openCidrs += '::/0' }

                            $portDisplay = if ($isAllTraffic) {
                                'All Ports'
                            }
                            elseif ($fromPort -eq $toPort) {
                                "$fromPort"
                            }
                            else {
                                "$fromPort-$toPort"
                            }

                            [PSCustomObject]@{
                                GroupId     = $sg.GroupId
                                GroupName   = $sg.GroupName
                                VpcId       = $sg.VpcId
                                Protocol    = if ($isAllTraffic) { 'All' } else { $rule.IpProtocol }
                                Ports       = $portDisplay
                                OpenCIDR    = $openCidrs -join ', '
                                Description = ($rule.Ipv4Ranges | Where-Object { $_.CidrIp -eq '0.0.0.0/0' } |
                                    Select-Object -First 1 -ExpandProperty Description) -as [string]
                            }
                        }
                    }
                }
            }

            if ($findings) {
                Write-Verbose "Found $($findings.Count) overly permissive rule(s) across security groups."
                $findings
            }
            else {
                Write-Verbose "No overly permissive inbound rules found. All 0.0.0.0/0 rules are limited to ports: $($AllowedPorts -join ', ')"
                return [PSCustomObject]@{}
            }
        }
        catch {
            Write-Error "Failed to retrieve security groups: $_"
        }
    }
}

<#
.SYNOPSIS
    Finds security groups that allow inbound traffic on common database ports.

.DESCRIPTION
    Scans all EC2 security groups in the current region and returns those with
    inbound rules permitting traffic on well-known database ports (MySQL, PostgreSQL,
    MSSQL, Oracle, Redis, MongoDB, etc.). Reports any source CIDR, not just
    0.0.0.0/0, so you can audit all DB-accessible security groups.

.PARAMETER Region
    AWS region to scan. Defaults to the current session region.

.PARAMETER ProfileName
    AWS credential profile name. Defaults to the current session profile.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.PARAMETER DatabasePorts
    Array of port numbers considered database ports. Defaults to common DB ports:
    1433 (MSSQL), 1521 (Oracle), 3306 (MySQL/MariaDB), 5432 (PostgreSQL),
    5439 (Redshift), 6379 (Redis), 27017 (MongoDB).

.NOTES
    Dependencies:
    - AWS.Tools.EC2 or AWSPowerShell

.EXAMPLE
    PS> Find-CCEC2DBSG.ps1
    Lists all security groups allowing inbound DB connections on default ports.

.EXAMPLE
    PS> Find-CCEC2DBSG.ps1 -DatabasePorts 3306, 5432
    Checks only MySQL and PostgreSQL ports.

.EXAMPLE
    PS> Find-CCEC2DBSG.ps1 -Region us-west-2
    Scans security groups in us-west-2.
#>

function Find-CCEC2DBSG {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int[]]$DatabasePorts = @(1433, 1521, 3306, 5432, 5439, 6379, 27017),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $portLabels = @{
            1433  = 'MSSQL'
            1521  = 'Oracle'
            3306  = 'MySQL/MariaDB'
            5432  = 'PostgreSQL'
            5439  = 'Redshift'
            6379  = 'Redis'
            27017 = 'MongoDB'
        }

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        try {
            $securityGroups = Get-EC2SecurityGroup @awsParams

            if (-not $securityGroups) {
                Write-Output "No security groups found."
                return
            }

            $results = @()

            foreach ($sg in $securityGroups) {
                foreach ($rule in $sg.IpPermissions) {
                    # Check if this rule covers any database port
                    $matchedPorts = @()

                    foreach ($dbPort in $DatabasePorts) {
                        $isMatch = $false

                        if ($rule.IpProtocol -eq '-1') {
                            # All traffic rule covers all ports
                            $isMatch = $true
                        }
                        elseif ($rule.FromPort -le $dbPort -and $rule.ToPort -ge $dbPort) {
                            $isMatch = $true
                        }

                        if ($isMatch) {
                            $label = if ($portLabels.ContainsKey($dbPort)) { "$dbPort ($($portLabels[$dbPort]))" } else { "$dbPort" }
                            $matchedPorts += $label
                        }
                    }

                    if ($matchedPorts.Count -eq 0) {
                        continue
                    }

                    # Collect source CIDRs
                    $sources = @()
                    foreach ($ipRange in $rule.Ipv4Ranges) {
                        $sources += $ipRange.CidrIp
                    }
                    foreach ($ipv6Range in $rule.Ipv6Ranges) {
                        $sources += $ipv6Range.CidrIpv6
                    }

                    if ($sources.Count -eq 0) {
                        continue
                    }

                    $results += [PSCustomObject]@{
                        GroupId      = $sg.GroupId
                        GroupName    = $sg.GroupName
                        VpcId        = $sg.VpcId
                        Protocol     = if ($rule.IpProtocol -eq '-1') { 'All' } else { $rule.IpProtocol }
                        MatchedPorts = ($matchedPorts | Sort-Object -Unique) -join ', '
                        SourceCIDRs  = ($sources) -join ', '
                    }
                }
            }

            if ($results.Count -eq 0) {
                Write-Output "No security groups with inbound database port rules found."
                return
            }

            $results | Sort-Object GroupId
        }
        catch {
            Write-Error "Error in $($MyInvocation.MyCommand.Name): $_"
            throw
        }
    }
}


<#
.SYNOPSIS
    Count of EC2 related objects within a region.

.DESCRIPTION
    Returns count of Instances, Volumes, Snapshots, AutoScaling groups,
    and Load Balancers for one or more regions.

.PARAMETER Region
    Region or list of regions to scan. If not provided, scans all regions.

.PARAMETER ProfileName
    AWS credential profile name. Defaults to the current session profile.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.EXAMPLE
    PS C:\> .\Get-CCEC2Count.ps1 | Format-Table

.EXAMPLE
    PS C:\> .\Get-CCEC2Count.ps1 -Region us-east-1, us-west-2 -ProfileName MyProfile
#>
function Get-CCEC2Count {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Region,

        # AWS common parameters
        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        # Build base AWS params (excludes Region since we iterate over regions)
        $baseAwsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
        $baseAwsParams.Remove('Region') | Out-Null

        # Resolve regions if not provided
        if (-not $Region) {
            $Region = (Get-EC2Region @baseAwsParams).RegionName
        }
    }

    process {
        $output = @()
        $totalRegions = $Region.Count
        $currentIndex = 0

        foreach ($R in $Region) {
            $currentIndex++
            $percentComplete = [math]::Round(($currentIndex / $totalRegions) * 100)
            Write-Progress -Activity 'Scanning EC2 Resources' -Status "Region: $R ($currentIndex of $totalRegions)" -PercentComplete $percentComplete
            Write-Verbose "Region: $R"

            # Region-specific splat (adds Region to the base awsParams)
            $regionParams = $baseAwsParams.Clone()
            $regionParams['Region'] = $R

            try {
                $RegionData = [PSCustomObject][ordered]@{
                    Region                = $R
                    InstanceCount         = @(Get-EC2Instance @regionParams).Count
                    VolumeCount           = @(Get-EC2Volume @regionParams).Count
                    VolCapacityInGb       = (Get-EC2Volume @regionParams | Measure-Object -Property Size -Sum).Sum
                    SnapshotCount         = @(Get-EC2Snapshot -OwnerId self @regionParams).Count
                    AutoScalingGroupCount = @(Get-ASAutoScalingGroup @regionParams).Count
                    LoadBalancerCount     = @(Get-ELB2LoadBalancer @regionParams).Count + @(Get-ELBLoadBalancer @regionParams).Count
                    ScanOk                = $true
                }
                Write-Verbose "$RegionData"
            }
            catch {
                Write-Verbose "catch: $R - $_"
                $RegionData = [PSCustomObject][ordered]@{
                    Region                = $R
                    InstanceCount         = ''
                    VolumeCount           = ''
                    VolCapacityInGb       = ''
                    SnapshotCount         = ''
                    AutoScalingGroupCount = ''
                    LoadBalancerCount     = ''
                    ScanOk                = $false
                }
            }
            finally {
                $output += $RegionData
            }
        }

        Write-Progress -Activity 'Scanning EC2 Resources' -Completed
        return $output
    }
}



# ================================================================================================
# Get-CCAllEC2Patch Function
# ================================================================================================

function Get-CCAllEC2Patch {
    <#
    .SYNOPSIS
        Retrieves patch compliance data for all EC2 instances.

    .DESCRIPTION
        Queries all EC2 instances in the target account/region, retrieves their SSM patch
        compliance state, and returns patch objects. Supports AWS common credential and
        region parameters via splatting for multi-account/region usage.

        Includes exponential backoff retry logic for API throttling.

    .PARAMETER Region
        The AWS region to query. Falls back to the default region if not specified.

    .PARAMETER ProfileName
        The AWS credential profile name to use.

    .PARAMETER AccessKey
        The AWS access key for explicit credentials.

    .PARAMETER SecretKey
        The AWS secret key for explicit credentials.

    .PARAMETER SessionToken
        The session token for temporary session-based credentials.

    .PARAMETER Credential
        An AWSCredentials object instance.

    .PARAMETER NetworkCredential
        Used with SAML-based authentication when ProfileName references a SAML role profile.

    .PARAMETER ProfileLocation
        The path to the ini-format credential file.

    .PARAMETER EndpointUrl
        The endpoint to make the call against.

    .EXAMPLE
        Get-CCAllEC2Patch -ProfileName 'production' -Region 'us-east-1'

        Retrieves patch data for all instances in the production account, us-east-1.

    .EXAMPLE
        Get-CCAllEC2Patch -AccessKey $ak -SecretKey $sk -SessionToken $st -Region 'eu-west-1'

        Retrieves patch data using explicit temporary credentials.

    .EXAMPLE
        Get-CCAllEC2Patch -Region 'us-east-1' | Export-Csv -Path 'patches.csv' -NoTypeInformation

        Exports patch compliance report to CSV.

    .NOTES
        Generated by Kiro using Auto, reviewed by ccharland
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
        Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
        Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$Region,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ProfileName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$AccessKey,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SecretKey,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SessionToken,

        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$Credential,

        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$NetworkCredential,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ProfileLocation,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$EndpointUrl
    )

    begin {
        # Build AWS credential/region splat from bound parameters
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $UTCDate = Get-Date | Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        $report = New-Object System.Collections.ArrayList
    }

    process {
        $instances = (Get-EC2Instance @awsParams).Instances.InstanceId
        Write-Verbose "Found $($instances.Count) instances"
        foreach ($id in $instances) {
            $patches = $null
            $retryCount = 0
            $maxRetries = 5
            $baseDelay = 2
            Write-Verbose "Starting Get-SSMInstancePatch for $id"
            while ($retryCount -lt $maxRetries) {
                try {
                    $patches = @(Get-SSMInstancePatch -InstanceId $id @awsParams -ErrorAction Stop)
                    break
                }
                catch {
                    if ($_.Exception.Message -match "Rate exceeded|Throttling") {
                        $retryCount++
                        if ($retryCount -ge $maxRetries) {
                            Write-Warning "Failed to get patches for $id after $maxRetries retries. Skipping."
                            break
                        }
                        $delay = $baseDelay * [Math]::Pow(2, $retryCount - 1) + (Get-Random -Minimum 0 -Maximum 1000) / 1000
                        Write-Verbose "Rate limited on $id, retry $retryCount/$maxRetries in $([Math]::Round($delay, 1))s..."
                        Start-Sleep -Seconds $delay
                    }
                    else {
                        Write-Warning "Error getting patches for ${id}: $($_.Exception.Message). Skipping."
                        break
                    }
                }
            }

            if (-not $patches -or $patches.Count -eq 0) {
                Write-Verbose "No patches seen for $id"
                continue
            }

            Write-Information -MessageData "Instance $id has $($patches.Count) patches" -Tags "Summary"

            foreach ($p in $patches) {
                $newitem = [PSCustomObject]@{
                    ReportTime     = $UTCDate
                    InstanceId     = $id
                    Title          = $p.Title
                    KBId           = $p.KBId
                    State          = $p.State
                    Classification = $p.Classification
                    Severity       = $p.Severity
                    InstalledTime  = $p.InstalledTime
                }
                [void]$report.Add($newitem)
            }
        }
    }

    end {
        $report
    }
}



# ================================================================================================
# Module Exports
# ================================================================================================

# Export all functions
Export-ModuleMember -Function @(
    'Get-CCEC2SGInUse',
    'Get-CCEC2Count',
    'Find-CCEC2DBSG',
    'Out-CCAWSSupportingInfo',
    'Out-CCAWSNetworkingComponent',
    'Get-CCIAMAuditList',
    'Get-CCGlobalAuditReportItem',
    'Get-CCEC2KeyTagNameStatus',
    'Get-CCEC2SnapshotReport',
    'Get-CCEC2VolumeReport',
    'Start-CCEC2RetryLoop',
    'Find-CCOpenSecurityGroup',
    'Get-CCAllEC2Patch'
)

# SIG # Begin signature block
# MIImXQYJKoZIhvcNAQcCoIImTjCCJkoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBhUitxxIjBNOEe
# teW7Or/xkr11cTs/XcrAfsHUTIR5jqCCH3IwggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUA
# MFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNV
# BAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAz
# MjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCb
# K51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZ
# UKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYk
# wmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE2
# 15wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+
# 8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9
# JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+
# EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9
# o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sC
# AwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0G
# A1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYD
# VR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDAS
# MAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwu
# c2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmww
# ewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUF
# BzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEA
# Bv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug
# 2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCy
# KppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099i
# ChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj
# 1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO3
# 7PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqm
# KL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTq
# lLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQ
# ZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWU
# H3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63
# Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZMMIIEtKADAgECAhAV
# VO/doV4MRRGuXmkecKnEMA0GCSqGSIb3DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGlj
# IENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjMwODA5MDAwMDAwWhcNMjYwODA4MjM1
# OTU5WjBjMQswCQYDVQQGEwJVUzEWMBQGA1UECAwNTmV3IEhhbXBzaGlyZTEdMBsG
# A1UECgwUQ2hyaXN0b3BoZXIgQ2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVy
# IENoYXJsYW5kMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwLQAcUKQ
# zYs2WJY+W2fl+/1PzX3vsFwK/W9sj1RXRLBsQjsTCYRu+jRPEZSVzL/K4L877Wxb
# 69/ye88/RrWS0d6LUyohl0OgJwgRBXBsDIcpt3hTv7GRLAFvjzcCOvK6qk+kjf+b
# xqYSUOxfl/XDK0QvM3KgWbq2IeNHoMwvAXVFBcZnRPXp1FkcHGKf+nNwxP6VGWti
# RrhIj99q0R4iwOQaQLRY8pe8m1wn/gwFRai1F1f/Q2EMSyvbgf7kYpFNHJK17LZR
# 9J/G7P8h4QFQZJdMU6C4lRT+Lk2jEDF4elKF5c7DFjfMv2zd0jf3/2vOhaycGna9
# puKwQUvtwtrmcCwOI5EXBIVBcFVS8xD6eeREvzjZXiuS83quzwxVVjNBQ2f/nuK5
# 4huEBbNQQeNjSkMdjyr5S0Xwf8Pic5NA4ggLUWuv2XYqTTMtXHQPZ41noEJM+LSB
# ulBatGT98Tu0kib3MH7e1vREcTG7gZDnicmY0RfrWM59txft97gXP7Vj99ed9t2/
# 9niQleiT+YXy3ZpNoqGFB3XC13mM44xEff49vRSLN/B0IonG5vDpMgtFoKpqPtUx
# /oKQWtYbmoWFZkvEBRUeJOmkEmIUQonzE7aqgk/uGtyjxsBHtJzIHojA+8fGeD0N
# XjlOM1bbT0OcpSMkhRXPqiOELViMQwHrAiUCAwEAAaOCAYkwggGFMB8GA1UdIwQY
# MBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSO6WwZWwCa6iKws6LE
# 4InGvJQl3zAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAK
# BggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUF
# BwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwSQYDVR0fBEIw
# QDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29k
# ZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsGAQUFBzAChjho
# dHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NB
# UjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJ
# KoZIhvcNAQEMBQADggGBAENPYZO6JkhXuprRcjFErvAggFDfB4bJmvHwydUUq8EE
# dDkvVvS+SnqpaL+Nw5FY/X5GnIXfWKYvQJFY1o/bskqLBSH96jOk+wMWZ2LqfuyE
# uW4OZUvBtpho2E2QwcpCQQzG47c+qtENC6lITctyoOUi5481cm9VXRL0E1g/MSDO
# qpYcd32oKt6rbqLQZD89HFgkNrfh3a4wq2O8ljai9gvQJnYV4588DGI4quzv81b6
# mGDx9ku9zHhtvI19C1L+oQddqFFUViSwUUiNrBO7aA5iFwr1vQPkiP40Zd6fSSQA
# jrRnUI/kbK9oD2l1i/Vi9hfQ8SLarLPhW0M0qaut175+RJKlwuusUZADtgYVWcrm
# Mxy20RMCUZA2bnTWXjb4pVfHUyKPU7dpM+8gG/tUPBZegMWrzWqctSPQhdREpkLT
# MCm5E/o4ZUGNE0uo+twbGMGEyPPmjsFnIKLAqN2rHMI1Fz9pR+qMdixl+/mG/ElS
# JqGSDVArmZLn1IYhr4vQ8DCCBmIwggTKoAMCAQICEQCkKTtuHt3XpzQIh616Trck
# MA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# Q0EgUjM2MB4XDTI1MDMyNzAwMDAwMFoXDTM2MDMyMTIzNTk1OVowcjELMAkGA1UE
# BhMCR0IxFzAVBgNVBAgTDldlc3QgWW9ya3NoaXJlMRgwFgYDVQQKEw9TZWN0aWdv
# IExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcg
# U2lnbmVyIFIzNjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANOElfRu
# pFN48j0QS3gSBzzclIFTZ2Gsn7BjsmBF659/kpA2Ey7NXK3MP6JdrMBNU8wdmkf+
# SSIyjX++UAYWtg3Y/uDRDyg8RxHeHRJ+0U1jHEyH5uPdk1ttiPC3x/gOxIc9P7Gn
# 3OgW7DQc4x07exZ4DX4XyaGDq5LoEmk/BdCM1IelVMKB3WA6YpZ/XYdJ9JueOXeQ
# ObSQ/dohQCGyh0FhmwkDWKZaqQBWrBwZ++zqlt+z/QYTgEnZo6dyIo2IhXXANFkC
# HutL8765NBxvolXMFWY8/reTnFxk3MajgM5NX6wzWdWsPJxYRhLxtJLSUJJ5yWRN
# w+NBqH1ezvFs4GgJ2ZqFJ+Dwqbx9+rw+F2gBdgo4j7CVomP49sS7CbqsdybbiOGp
# B9DJhs5QVMpYV73TVV3IwLiBHBECrTgUfZVOMF0KSEq2zk/LsfvehswavE3W4aBX
# JmGjgWSpcDz+6TqeTM8f1DIcgQPdz0IYgnT3yFTgiDbFGOFNt6eCidxdR6j9x+kp
# cN5RwApy4pRhE10YOV/xafBvKpRuWPjOPWRBlKdm53kS2aMh08spx7xSEqXn4QQl
# dCnUWRz3Lki+TgBlpwYwJUbR77DAayNwAANE7taBrz2v+MnnogMrvvct0iwvfIA1
# W8kp155Lo44SIfqGmrbJP6Mn+Udr3MR2oWozAgMBAAGjggGOMIIBijAfBgNVHSME
# GDAWgBRfWO1MMXqiYUKNUoC6s2GXGaIymzAdBgNVHQ4EFgQUiGGMoSo3ZIEoYKGb
# MdCM/SwCzk8wDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEoGA1Ud
# HwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y1RpbWVTdGFtcGluZ0NBUjM2LmNybDB6BggrBgEFBQcBAQRuMGwwRQYIKwYBBQUH
# MAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFt
# cGluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5j
# b20wDQYJKoZIhvcNAQEMBQADggGBAAKBPqSGclEh+WWpLj1SiuHlm8xLE0SThI2y
# Luq+75s11y6SceBchpnKpxWaGtXc8dya1Aq3RuW//y3wMThsvT4fSba2AoSWlR67
# rA4fTYGMIhgzocsids0ct/pHaocLVJSwnTYxY2pE0hPoZAvRebctbsTqENmZHyOV
# jOFlwN2R3DRweFeNs4uyZN5LRJ5EnVYlcTOq3bl1tI5poru9WaQRWQ4eynXp7Pj0
# Fz4DKr86HYECRJMWiDjeV0QqAcQMFsIjJtrYTw7mU81qf4FBc4u4swphLeKRNyn9
# DDrd3HIMJ+CpdhSHEGleeZ5I79YDg3B3A/fmVY2GaMik1Vm+FajEMv4/EN2mmHf4
# zkOuhYZNzVm4NrWJeY4UAriLBOeVYODdA1GxFr1ycbcUEGlUecc4RCPgYySs4d00
# NNuicR4a9n7idJlevAJbha/arIYMEuUqTeRRbWkhJwMKmb9yEvppRudKyu1t6l21
# sIuIZqcpVH8oLWCxHS0LpDRF9Y4jijCCBoIwggRqoAMCAQICEDbCsL18Gzrno7Pd
# NsvJdWgwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpO
# ZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVT
# RVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3QgUlNBIENlcnRpZmlj
# YXRpb24gQXV0aG9yaXR5MB4XDTIxMDMyMjAwMDAwMFoXDTM4MDExODIzNTk1OVow
# VzELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEuMCwGA1UE
# AxMlU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBSb290IFI0NjCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAIid2LlFZ50d3ei5JoGaVFTAfEkFm8xa
# FQ/ZlBBEtEFAgXcUmanU5HYsyAhTXiDQkiUvpVdYqZ1uYoZEMgtHES1l1Cc6HaqZ
# zEbOOp6YiTx63ywTon434aXVydmhx7Dx4IBrAou7hNGsKioIBPy5GMN7KmgYmuu4
# f92sKKjbxqohUSfjk1mJlAjthgF7Hjx4vvyVDQGsd5KarLW5d73E3ThobSkob2SL
# 48LpUR/O627pDchxll+bTSv1gASn/hp6IuHJorEu6EopoB1CNFp/+HpTXeNARXUm
# dRMKbnXWflq+/g36NJXB35ZvxQw6zid61qmrlD/IbKJA6COw/8lFSPQwBP1ityZd
# wuCysCKZ9ZjczMqbUcLFyq6KdOpuzVDR3ZUwxDKL1wCAxgL2Mpz7eZbrb/JWXiOc
# NzDpQsmwGQ6Stw8tTCqPumhLRPb7YkzM8/6NnWH3T9ClmcGSF22LEyJYNWCHrQqY
# ubNeKolzqUbCqhSqmr/UdUeb49zYHr7ALL8bAJyPDmubNqMtuaobKASBqP84uhqc
# RY/pjnYd+V5/dcu9ieERjiRKKsxCG1t6tG9oj7liwPddXEcYGOUiWLm742st50jG
# wTzxbMpepmOP1mLnJskvZaN5e45NuzAHteORlsSuDt5t4BBRCJL+5EZnnw0ezntk
# 9R8QJyAkL6/bAgMBAAGjggEWMIIBEjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dib
# wJ3ysgNmyzAdBgNVHQ4EFgQU9ndq3T/9ARP/FqFsggIv0Ao9FCUwDgYDVR0PAQH/
# BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wEwYDVR0lBAwwCgYIKwYBBQUHAwgwEQYD
# VR0gBAowCDAGBgRVHSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwudXNl
# cnRydXN0LmNvbS9VU0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5LmNy
# bDA1BggrBgEFBQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAA6+ZUHtaES45aHF1BGH5Lc7JYzr
# ftrIF5Ht2PFDxKKFOct/awAEWgHQMVHol9ZLSyd/pYMbaC0IZ+XBW9xhdkkmUV/K
# bUOiL7g98M/yzRyqUOZ1/IY7Ay0YbMniIibJrPcgFp73WDnRDKtVutShPSZQZAdt
# FwXnuiWl8eFARK3PmLqEm9UsVX+55DbVIz33Mbhba0HUTEYv3yJ1fwKGxPBsP/Mg
# TECimh7eXomvMm0/GPxX2uhwCcs/YLxDnBdVVlxvDjHjO1cuwbOpkiJGHmLXXVNb
# sdXUC2xBrq9fLrfe8IBsA4hopwsCj8hTuwKXJlSTrZcPRVSccP5i9U28gZ7OMzoJ
# GlxZ5384OKm0r568Mo9TYrqzKeKZgFo0fj2/0iHbj55hc20jfxvK3mQi+H7xpbzx
# ZOFGm/yVQkpo+ffv5gdhp+hv1GDsvJOtJinJmgGbBFZIThbqI+MHvAmMmkfb3fTx
# mSkop2mSJL1Y2x/955S29Gu0gSJIkc3z30vU/iXrMpWx2tS7UVfVP+5tKuzGtgkP
# 7d/doqDrLF1u6Ci3TpjAZdeLLlRQZm867eVeXED58LXd1Dk6UvaAhvmWYXoiLz4J
# A5gPBcz7J311uahxCweNxE+xxxR3kT0WKzASo5G/PyDez6NHdIUKBeE3jDPs2ACc
# 6CkJ1Sji4PKWVT0/MYIGQTCCBj0CAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAVVO/doV4MRRGuXmkecKnEMA0GCWCGSAFlAwQCAQUA
# oIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEIDBCIyT3gFOseh42C8kI/EtdG3lqCVCxvrdRT+5qnRkvMA0GCSqGSIb3
# DQEBAQUABIICAEZkY4kqD1Dzrq9enKbYs1YTBvVk32fXhhjfhPNnC7LPo5fFgFy6
# 5v6wrFOhGychXn0xNfuOOj14sBkip1hO5TyJGky8BlpiVDNs4efC2MolbaKRbrnE
# zb0ILS/Hb4ytK2SwptxDThHS9ysnsHGj1PKxvja3MyCQMmkhTSWPen8AFEk91phQ
# EvetixAvWgpmKTojVRFqvb+Gw0Md2zM/v7VywGbX2j0q7gQcY1pCI+Qqn5W6Rp1U
# T6SDXuW6tPuE7DCDFI7/816F0mJ6DD7r6yAu2IFd0QuDtgdPTzeMios0piDbav/q
# n1pa2qUilNr0CRE0z63yfhEatrUCdX8uSfCCD70ct5VF4iJLXjzzoqU9xUcTsY1k
# ycUe1GMKfZ1omyXz2wqr5rT5JEhybUEEDJYMgOh9h2muF2/WtcxW1IDKvAClQeeL
# VlqCXjqsWCRMklBFjABVIM0kmUbKyYNv671EUrI3MQIljTN82tuvrYS9VVNyOGiY
# Uw3qEge1sHq4j/+dNbAKeb+UsHOcUKVWDzXD5DkcSSwPvGsELnBtOLbqXe96LkYa
# yph4eIyWRvNAnWsJGjNtdFG36wijq237Acep2ae1V352fXIPnAXiROo+6DQWaN3r
# VXm0X2OOUXKdX/PBtJQeeH9yDDdoFbF32qV+Q1XI2OB2OShtNU+gknkXoYIDIzCC
# Ax8GCSqGSIb3DQEJBjGCAxAwggMMAgEBMGowVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYCEQCkKTtuHt3XpzQIh616TrckMA0GCWCGSAFlAwQC
# AgUAoHkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwNjExMTkzMTIzWjA/BgkqhkiG9w0BCQQxMgQw+a66cOBIwQxrpR8g5tyMMSQo
# ACBVaWIc8wAExMYzYb0xi2SX67pfMCboKyQajPfSMA0GCSqGSIb3DQEBAQUABIIC
# AIdJXd2ZuRL5S5jKegPLwSrGbetDEZzeOqzrBqoN8jjoCLwETnQjT8qpmunE7yNi
# n74R9NKYiL6Ah6vwVVJm53q/WRDEMjre6WzbqjZG6V15CedP5QIWBuofzg3wtVFD
# OOF6g6HApoLhQw67Si0hf9GufUvFRZqeRCuKSxH9nLwuCBpP1dnQ3ZAhkKUxqVrO
# Wh30Z9YWNY611+HbwchfqqoQC47olL5YYtnaXIVYswB0QRhApm1tgzGupqFpUWPZ
# 4Gj2jTgkcP8V4l8ZDYsZAwa8EkP4wxg6sj5ht3L5dIv8YKHuAQD0CI13dQfavU44
# 9g7hunQeYuMPeaKxtCVnAW7+O9jvgTCoUvKHrvLidwxKV6kNl3pBq/u1zi30dcNr
# NQWhM8PGcoHHFoG8WmggX2DYyqFWCLdpzT6wPKqa49gERQOX715eR0n3v+fxoenT
# el0xypXCKntw8+LsmXUeuO4KRBJEPP5J9k6UFsAJ8d/18MYzCnuxHZcF9BfPOU5K
# rolNXcEl3p+nfVtfmDUjDdPjwyfeCPjZ7qJ/A+oT04snToFql9FlJd24uKCgX8Fc
# d/yLDgvSkq9fOGkX7iYJs4aHZ+hQb7g1nIlzYvtNEriIot362dDrIOiiSB65v2Hl
# AoFkp4I/DRbEEt0uX2zd3F+dQG4BUVa1jxPYBkHB8Mp1
# SIG # End signature block
