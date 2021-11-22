# this entire Lambda function exists to work around cloudformation limitations, namely:
# 1. Lack of support for complete configuration of Cognito User Pool Clients
# 2. Subsequent inability to define Lamdba fucntions > 4096 characters inline.
# Both of these are highly annoying limitations of something that should be well
# support by now </rant>
#
# Anyway, here it is. These functions should be used to manage user pool clients in the context
# of Lambda-backed custom resources ONLY! It doesn't make a whole heap of sense to try and execute thses
# functions outside of that context.

import boto3
from botocore.exceptions import ClientError
from botocore.vendored import requests
from multiprocessing import Process, Pipe
import json
import logging

# Cloudformation response values
CFN_SUCCESS = "SUCCESS"
CFN_FAILED = "FAILED"

# Cognito Identity Provider Client
client_idp = boto3.client('cognito-idp')

# Note: This function is normally included when defining Lambda-backed custom resources
# inline within CloudFormation templates. However, our custom resources for Cognito
# are larger than the 4096 character limit for inline definition. Oh dear. That means
# that our custom resource is too big to live inside the cloudformation template.
# BUT if it's not inside the cloudformation template, we can't just include the cfnresponse
# module, since that's only supplied by Cloudformation itself, hence we must reproduce it here. GAH.
#
# This function is the same as the contents of the cfnresponse module, taken from this URL:
# https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-lambda-function-code-cfnresponsemodule.html
def cfn_response_send(event, context, responseStatus, responseData, physicalResourceId=None, noEcho=False):
# -----------------------------------------------------------------------------------------------------------------
    responseUrl = event['ResponseURL']
 
    print(responseUrl)
 
    responseBody = {}
    responseBody['Status'] = responseStatus
    responseBody['Reason'] = 'See the details in CloudWatch Log Stream: ' + context.log_stream_name
    responseBody['PhysicalResourceId'] = physicalResourceId or context.log_stream_name
    responseBody['StackId'] = event['StackId']
    responseBody['RequestId'] = event['RequestId']
    responseBody['LogicalResourceId'] = event['LogicalResourceId']
    responseBody['NoEcho'] = noEcho
    responseBody['Data'] = responseData
 
    json_responseBody = json.dumps(responseBody)
 
    print("Response body:\n" + json_responseBody)
 
    headers = {
        'content-type' : '',
        'content-length' : str(len(json_responseBody))
    }
 
    try:
        response = requests.put(responseUrl,
                                data=json_responseBody,
                                headers=headers)
        print("Status code: " + response.reason)
    except Exception as e:
        print("send(..) failed executing requests.put(..): " + str(e))

# -----------------------------------------------------------------------------------------------------------------    
# IDENTITY PROVIDER
# -----------------------------------------------------------------------------------------------------------------  

def create_provider(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------    
    try:
        resp = client_idp.create_identity_provider(**params)
        results_pipe.send({'Result': True, 'Message': "Created SAML Idp: " + str(resp['IdentityProvider']['IdpIdentifiers'][0]), 'Data': resp['IdentityProvider']})
    except Exception as e:
        print(e)
        results_pipe.send({'Result': False, 'Message': "Cannot create SAML Idp: " + str(e), 'Data': {}})

    results_pipe.close()

def update_provider(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------
    try:
        resp = client_idp.update_identity_provider(**params)
        results_pipe.send({'Result': True, 'Message': "Updated SAML Idp: " + resp['IdpIdentifiers'], 'Data': resp['IdentityProvider']})
    except Exception as e:
        results_pipe.send({'Result': False, 'Message': "Cannot update SAML Idp: " + str(e), 'Data': {}})

    results_pipe.close()

def delete_provider(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------              
    try:
        client_idp.delete_identity_provider(**params)
        results_pipe.send({'Result': True, 'Message': "SAML identity provider deleted", 'Data': {}})
    except ClientError as e:
        if e.response['Error']['Code'] == "NoSuchEntity":
            results_pipe.send({'Result': True, 'Message': "SAML Idp does not exist. Skipping deletion.", 'Data': {}})
        else:
            results_pipe.send({'Result': False, 'Message': "Cannot delete SAML Idp: " + str(e), 'Data': {}})
    except Exception as e:
        results_pipe.send({'Result': True, 'Message': "Cannot delete SAML Idp: " + str(e), 'Data': {}})

    results_pipe.close()

# -----------------------------------------------------------------------------------------------------------------    
# CLIENT
# -----------------------------------------------------------------------------------------------------------------    

def create_client(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------    
    try:
        print(params)
        resp = client_idp.create_user_pool_client(**params)
        results_pipe.send({'Result': True, 'Message': "Successfully created User Pool client", 'Data': resp['UserPoolClient']})
    except Exception as e:
        results_pipe.send({'Result': False, 'Message': "Create Failed: " + str(e), 'Data': {}})

    results_pipe.close()

def update_client(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------
    try:
        # Try to list existing resources with the same details.
        # We only have the client name, not the ID. We need that ID
        # to perform an update. Don't worry about pagination - there won't be hundreds (hopefully!)
        response = client_idp.list_user_pool_clients(UserPoolId=params['UserPoolId'], MaxResults=10)
        for client in response['UserPoolClients']:
            if client['ClientName'] == params['ClientName']:
                logging.info('Found existing user pool client')                
                client_id = client['ClientId']
                break

        # If we didn;t find a client ID, we're a bit stuffed.
        if client_id is None or len(client_id) <= 0 or client_id == "":
            raise ValueError('Client ID for name \'{0}\' not found!'.format(params['ClientName']))

        # Otherwise, orsum. Update the parameters with the ID
        params.update({'ClientId': client_id})

        # Update the client with the passed parameters
        resp = client_idp.update_user_pool_client(**params)
        results_pipe.send({'Result': True, 'Message': "Updated user pool client", 'Data': resp['UserPoolClient']})

    except Exception as e:
        results_pipe.send({'Result': False, 'Message': "Update Failed: " + str(e), 'Data': {}})

    # Get outta here.
    results_pipe.close()

def delete_client(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------              
    try:
        client_idp.delete_user_pool_client(**params)
        results_pipe.send({'Result': True, 'Message': "Deleted user pool client", 'Data': {}})
    except ClientError as e:
        if e.response['Error']['Code'] == "NoSuchEntity":
            results_pipe.send({'Result': True, 'Message': "Client does not exist!", 'Data': {}})
        else:
            results_pipe.send({'Result': False, 'Message': "Delete Failed: " + str(e), 'Data': {}})
    except Exception as e:
        results_pipe.send({'Result': True, 'Message': "Delete Failed: " + str(e), 'Data': {}})
        
    results_pipe.close()

# -----------------------------------------------------------------------------------------------------------------    
# DOMAIN
# -----------------------------------------------------------------------------------------------------------------    

def create_domain(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------        
    try:
        print(params)
        resp = client_idp.create_user_pool_domain(**params)
        results_pipe.send({'Result': True, 'Message': "Created User Pool Domain", 'Data': resp})
    except Exception as e:
        results_pipe.send({'Result': False, 'Message': "Cannot create User Pool Domain: " + str(e), 'Data': {}})
    
    results_pipe.close()

def update_domain(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------        
    try:
        resp = client_idp.update_user_pool_domain(**params)
        results_pipe.send({'Result': True, 'Message': "Updated User Pool Domain: " + resp['CloudFrontDomain'], 'Data': resp})
    except Exception as e:
        results_pipe.send({'Result': False, 'Message': "Cannot update User Pool Domain: " + str(e), 'Data': {}})
    
    results_pipe.close()

def delete_domain(params, results_pipe):
# -----------------------------------------------------------------------------------------------------------------        
    try:
        client_idp.delete_user_pool_domain(**params)
        results_pipe.send({'Result': True, 'Message': "User Pool Domain deleted", 'Data': {}})
    except ClientError as e:
        if e.response['Error']['Code'] == "NoSuchEntity":
            results_pipe.send({'Result': True, 'Message': "User Pool Domain does not exist. Skipping deletion.", 'Data': {}})
        else:
            results_pipe.send({'Result': False, 'Message': "Cannot delete User Pool Domain: " + str(e), 'Data': {}})
    except Exception as e:
        results_pipe.send({'Result': True, 'Message': "Cannot delete User Pool Domain: " + str(e), 'Data': {}})
    
    results_pipe.close()


# =================================================================================================================
# HANDLERS
# =================================================================================================================

# User Pool Client
def client_handler(event, context):   
# -----------------------------------------------------------------------------------------------------------------                  
    user_pool_id = event['ResourceProperties']['UserPoolId']
    client_name = event['ResourceProperties']['ClientName']
    explicit_auth_flows = event['ResourceProperties']['ExplicitAuthFlows']
    identity_providers = event['ResourceProperties']['SupportedIdps']
    allowed_oauth_flows_user_pool_client = str(event['ResourceProperties']['AllowedOAuthFlowsUserPoolClient']).lower() in ['true', '1', 't', 'y', 'yes', 'yeah', 'yup', 'aye']
    allowed_oauth_flows = event['ResourceProperties']['AllowedOAuthFlows']
    allowed_oauth_scopes = event['ResourceProperties']['AllowedOAuthScopes']
    callback_urls = event['ResourceProperties']['CallbackURLs']
    logout_urls = event['ResourceProperties']['LogoutURLs']

    generate_secret = str(event['ResourceProperties']['GenerateSecret']).lower() in ['true', '1', 't', 'y', 'yes', 'yeah', 'yup', 'aye']

    # Configure common parameters here
    params = {
        'UserPoolId': user_pool_id,
        'ClientName': client_name,
        'RefreshTokenValidity': 14,
        'ExplicitAuthFlows': explicit_auth_flows.split(","),
        'SupportedIdentityProviders': identity_providers.split(","),
        'AllowedOAuthFlowsUserPoolClient': allowed_oauth_flows_user_pool_client,
        'AllowedOAuthFlows': allowed_oauth_flows.split(","),
        'AllowedOAuthScopes': allowed_oauth_scopes.split(","),
        'CallbackURLs': callback_urls,
        'LogoutURLs': logout_urls
    }

    parent_end, child_end = Pipe()

    try:
        if event['RequestType'] == 'Create':
            params.update({'GenerateSecret': generate_secret})
            p = Process(target=create_client, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']
        elif event['RequestType'] == 'Update':         
            p = Process(target=update_client, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']
        elif event['RequestType'] == 'Delete':
            p = Process(target=delete_client, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']
        else:
            result = False
            message = "Unknown operation: " + event['RequestType']
            data = {}
    except Exception as e:
        result = False
        message = "Failed to complete CloudFormation action: " + str(e)
        data = {}

    # Provide the full response data object to allow us to grab outputs in CloudFormation
    # Note, we should remvoe datetimes, since they're not serializable
    responseData = data
    responseData['Reason'] = message
    responseData.pop('LastModifiedDate', None)
    responseData.pop('CreationDate', None)

    if result:
        cfn_response_send(event, context, CFN_SUCCESS, responseData)
    else:
        cfn_response_send(event, context, CFN_FAILED, responseData)


# User Pool Identity Provider
def identity_provider_handler(event, context):   
# -----------------------------------------------------------------------------------------------------------------                  
    provider_xml = event['ResourceProperties']['Metadata']
    provider_name = event['ResourceProperties']['Name']
    provider_identifier = event['ResourceProperties']['IdpIdentifier']
    user_pool_id = event['ResourceProperties']['UserPoolId']

    params = {
        'UserPoolId': user_pool_id,
        'ProviderName': provider_name,
    }

    attribute_mapping = {
        'Username': 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn',
        'name': 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name',
        'email': 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
        'family_name': 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname',
        'given_name': 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname',
        'nickname': 'http://schemas.xmlsoap.org/claims/CommonName'
    }

    idp_identifiers=[
        provider_identifier
    ]

    parent_end, child_end = Pipe()

    try:
        if event['RequestType'] == 'Create':
            params.update({'ProviderDetails': {'MetadataURL': provider_xml}})
            params.update({'ProviderType': 'SAML'})
            params.update({'AttributeMapping': attribute_mapping})
            params.update({'IdpIdentifiers': idp_identifiers})
            p = Process(target=create_provider, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']            
        elif event['RequestType'] == 'Update':
            params.update({'ProviderDetails': {'MetadataURL': provider_xml}})
            params.update({'ProviderType': 'SAML'})
            params.update({'AttributeMapping': attribute_mapping})    
            params.update({'IdpIdentifiers': idp_identifiers})          
            p = Process(target=update_provider, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']            
        elif event['RequestType'] == 'Delete':
            p = Process(target=delete_provider, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']            
        else:
            result = False
            message = "Unknown operation: " + event['RequestType']
            data = {}
    except Exception as e:
        result = False
        message = "Failed to complete CloudFormation action: " + str(e)
        data = {}

    # Provide the full response data object to allow us to grab outputs in CloudFormation
    # Note, we should remvoe datetimes, since they're not serializable
    responseData = data
    responseData['Reason'] = message
    responseData.pop('LastModifiedDate', None)
    responseData.pop('CreationDate', None)
    
    if result:
        cfn_response_send(event, context, CFN_SUCCESS, responseData)
    else:
        cfn_response_send(event, context, CFN_FAILED, responseData)                


# User Pool Domain Handler
def domain_handler(event, context):            
# -----------------------------------------------------------------------------------------------------------------                      
    user_pool_id = event['ResourceProperties']['UserPoolId']
    domain_name = event['ResourceProperties']['DomainName']

    # Optional to help with DNS resolution etc.
    cert_arn = None
    if hasattr(event['ResourceProperties'], 'CertArn'):
        cert_arn = event['ResourceProperties']['CertArn']

    params = {
        'UserPoolId': user_pool_id,
        'Domain': domain_name
    }

    custom_domain_config = {
        'CertificateArn': cert_arn
    }

    parent_end, child_end = Pipe()

    try:
        if event['RequestType'] == 'Create':
            if cert_arn:
                params.update({'CustomDomainConfig': custom_domain_config})
            p = Process(target=create_domain, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']            
        elif event['RequestType'] == 'Update':
            # if cert_arn:
            #     params.update({'CustomDomainConfig': custom_domain_config})
            # p = Process(target=update_domain, args=(params, child_end,))
            # p.start()
            # res = parent_end.recv()
            # p.join(timeout=180)
            # result = False if p.exitcode > 0 else res['Result']
            # message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            # data = {} if p.exitcode > 0 else res['Data']
            result = True
            message = 'Update Not Supported in Lambda runtime version of Boto!'            
            data = {}            
            # Can you believe it?
        elif event['RequestType'] == 'Delete':
            p = Process(target=delete_domain, args=(params, child_end,))
            p.start()
            res = parent_end.recv()
            p.join(timeout=180)
            result = False if p.exitcode > 0 else res['Result']
            message = 'Operation timed-out!' if p.exitcode > 0 else res['Message']
            data = {} if p.exitcode > 0 else res['Data']            
        else:
            result = False
            message = "Unknown operation: " + event['RequestType']
            data = {}
    except Exception as e:
        result = False
        message = "Failed to complete CloudFormation action: " + str(e)
        data = {}

    # Provide the full response data object to allow us to grab outputs in CloudFormation
    # Note, we should remvoe datetimes, since they're not serializable
    responseData = data
    responseData['Reason'] = message
    responseData.pop('LastModifiedDate', None)
    responseData.pop('CreationDate', None)
    
    if result:
        cfn_response_send(event, context, CFN_SUCCESS, responseData)
    else:
        cfn_response_send(event, context, CFN_FAILED, responseData)