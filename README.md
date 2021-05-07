# Wordpress on Copilot

The [AWS Reference Architecture](https://docs.aws.amazon.com/whitepapers/latest/best-practices-wordpress/reference-architecture.html) for Wordpress is quite similar to what Copilot already deploys as part of its default environment config. In order to get wordpress working, we need a few components which Copilot can help us create. 

## Instructions

#### Clone this repository.
```
git clone git@github.com:bvtujo/copilot-wordpress.git
```
#### Set up a Copilot application
```
copilot app init wordpress
```
If you have a custom domain in your account, you can run: 
```
copilot app init --domain mydomain.com wordpress
```

#### Deploy an environment
```
copilot env init -n test --default-config --profile default
```

#### Deploy the RDS resources attached to the scheduled job
```
copilot init -t "Scheduled Job" --schedule "@daily" --dockerfile ./Dockerfile_job \
  --name wp-db-job
copilot deploy -n wp-db-job
```
This step will take about 10 minutes to complete as your database cluster comes up. This will create an Aurora MySQL cluster, database secret to hold the username and password, and all the networking to allow your services to communicate with the database.

#### Convert the RDS Secret to SSM Parameters
```
export COPILOT_APP=wordpress
export COPILOT_ENV=test
./convert-secret-to-ssm.sh wpclusterAuroraSecret
```
#### Get your security group ID for Aurora
```
SG_ID=$(aws ec2 describe-security-groups | jq -r '.SecurityGroups[] | select(.GroupName | contains("wpclusterSecurityGroup")) | .GroupId')
echo $SG_ID
```
This Security Group will need to go in your wordpress frontend container.

#### Initialize your wordpress service
```
copilot svc init --name fe --type "Load Balanced Web Service" --image wordpress:5 --port 80
```
This will set up your service by deploying an ECR repository and registering it in SSM so Copilot can recognize it. It will not, however, overwrite the manifest which already exists in this repository. 

Once you've run `copilot svc init`, you'll need to modify your manifest to specify the additional security group. This enables your frontend container to talk to the database.

In the manifest, replace {{$SG_ID}} with the value of the environment variable you defined in the last step. 
```yaml
# ./copilot/fe/manifest.yml

network:
  vpc:
    security_groups: [{{$SG_ID}}]
```
#### Deploy your wordpress container
```
copilot svc deploy -n fe
```


## Teardown

#### Delete your wordpress service
```
copilot svc delete --name fe
```
Because we're using a custom security group created by another Copilot job, we need to delete this service first so the security group can be deleted.

#### Delete the rest of the application
```
copilot app delete --name wordpress
```

