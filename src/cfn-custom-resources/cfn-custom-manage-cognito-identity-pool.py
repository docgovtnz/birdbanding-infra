# this entire Lambda function exists to work around cloudformation limitations with
# respect to Identity pools. Specifically, the role mapping aspects.</rant>
#
# These functions should be used to manage user pool clients in the context
# of Lambda-backed custom resources ONLY! It doesn't make a whole heap of sense to try and execute these
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

# =================================================================================================================
# HANDLERS
# =================================================================================================================

# Role Mapping Handler
def role_mapping_handler(event, context):   
# -----------------------------------------------------------------------------------------------------------------                  
    identity_provider = event['ResourceProperties']['IdentityProvider']
    mapping_type = event['ResourceProperties']['Type']
    ambiguous_role_resolution = event['ResourceProperties']['AmbiguousRoleResolution']
    rules_config = event['ResourceProperties']['RulesConfiguration'] if 'RulesConfiguration' in event['ResourceProperties'] else None

    try:
        # Make sure the identity provider is valid
        if (identity_provider is None) or (len(identity_provider) <= 0) or identity_provider == "":
            raise ValueError('Invalid value for identity provider')

        # Start Building up the response data
        data = {}
        data[identity_provider] = {
            'Type': mapping_type if mapping_type else 'Token',
            'AmbiguousRoleResolution': ambiguous_role_resolution if ambiguous_role_resolution else 'Deny',
        }

        # Only provide the rules configuration if valid to do so. This is wordy, but we
        # want to be nice and explicit with Cloudformation
        if (mapping_type == 'Rules') and (rules_config) and ('Rules' in rules_config) and (len(rules_config['Rules']) > 0):
            data.update({'RulesConfiguration': rules_config})

    except Exception as e:
        result = False
        message = "Failed to transform role mappings: " + str(e)
        data = {}

    # Provide the full response data object to allow us to grab outputs in CloudFormation
    responseData = {}
    responseData['RoleMapping'] = data
    cfn_response_send(event, context, CFN_SUCCESS, responseData)