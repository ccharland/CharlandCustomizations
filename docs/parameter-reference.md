# Common Credential and Region Parameters for all AWS cmdlets

-AccessKey <String>
The AWS access key for the user account. This can be a temporary access key if the corresponding session token is supplied to the -SessionToken parameter.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	AK

-Credential <AWSCredentials>
An AWSCredentials object instance containing access and secret key information, and optionally a token for session-based credentials.
Required?	False
Position?	Named
Accept pipeline input?	True (ByValue, ByPropertyName)

-EndpointUrl <String>
The endpoint to make the call against.Note: This parameter is primarily for internal AWS use and is not required/should not be specified for normal usage. The cmdlets normally determine which endpoint to call based on the region specified to the -Region parameter or set as default in the shell (via Set-DefaultAWSRegion). Only specify this parameter if you must direct the call to a specific custom endpoint.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)

-NetworkCredential <PSCredential>
Used with SAML-based authentication when ProfileName references a SAML role profile. Contains the network credentials to be supplied during authentication with the configured identity provider's endpoint. This parameter is not required if the user's default network identity can or should be used during authentication.
Required?	False
Position?	Named
Accept pipeline input?	True (ByValue, ByPropertyName)

-ProfileLocation <String>
Used to specify the name and location of the ini-format credential file (shared with the AWS CLI and other AWS SDKs)If this optional parameter is omitted this cmdlet will search the encrypted credential file used by the AWS SDK for .NET and AWS Toolkit for Visual Studio first. If the profile is not found then the cmdlet will search in the ini-format credential file at the default location: (user's home directory)\.aws\credentials.If this parameter is specified then this cmdlet will only search the ini-format credential file at the location given.As the current folder can vary in a shell or during script execution it is advised that you use specify a fully qualified path instead of a relative path.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	AWSProfilesLocation, ProfilesLocation

-ProfileName <String>
The user-defined name of an AWS credentials or SAML-based role profile containing credential information. The profile is expected to be found in the secure credential file shared with the AWS SDK for .NET and AWS Toolkit for Visual Studio. You can also specify the name of a profile stored in the .ini-format credential file used with the AWS CLI and other AWS SDKs.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	StoredCredentials, AWSProfileName

-Region <Object>
The system name of an AWS region or an AWSRegion instance. This governs the endpoint that will be used when calling service operations. Note that the AWS resources referenced in a call are usually region-specific.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	RegionToCall

-SecretKey <String>
The AWS secret key for the user account. This can be a temporary secret key if the corresponding session token is supplied to the -SessionToken parameter.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	SK, SecretAccessKey

-SessionToken <String>
The session token if the access and secret keys are temporary session-based credentials.
Required?	False
Position?	Named
Accept pipeline input?	True (ByPropertyName)
Aliases	ST




