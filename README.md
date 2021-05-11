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

An environment is a collection of networking resources including a VPC, public and private subnets, an ECS Cluster, and (when necessary) an Application Load Balancer to serve traffic to your containers. Creating an environment is a prerequisite to deploying a service with Copilot. 

#### Create your frontend Wordpress service
```
copilot init -t "Load Balanced Web Service" --dockerfile ./Dockerfile --port 8080 --name fe
```

This will register a new service with Copilot so that it can easily be deployed to your new environment. It will write a manifest file at `copilot/fe/manifest.yml` containing simple, opinionated, extensible configuration for your service. If you've cloned this github repository, you may have noticed that there is already a file at that path. This command will not overwrite the existing file! 

#### Set up EFS
Wordpress needs a filesystem to store uploaded user content, themes, plugins, and some configuration files. We can do this with Copilot's built-in [managed EFS capability](https://aws.github.io/copilot-cli/docs/developing/storage/).

Modify the newly created manifest (or use the one provided with this repository) so that it includes the following lines:

```yaml
storage:
  volumes:
    wp-content:
      path: /var/www/html/wp-content
      read_only: false
      efs: true
```
This tells Copilot to create a filesystem in your environment, create a dedicated sub-directory for your service in that filesystem, and use that directory to store everything the wordpress installation needs. 

#### Set up your database for wordpress.
Wordpress also needs a database. We can set this up with Copilot's `storage init` command, which takes advantage of the [Additional Resources](https://aws.github.io/copilot-cli/docs/developing/additional-aws-resources/) functionality to simplify your experience configuring serverless databases.

```bash
copilot storage init -n wp -t Aurora --initial-db main --engine MySQL -w fe
```

The Cloudformation template which this command creates at `copilot/fe/addons/wp.yml` will create a serverless, autoscaling MySQL cluster named `wp` and an initial table called `main`. We'll set up Wordpress to work with this database.

It will also create a secret which contains metadata about your cluster. This secret is injected into your containers in the next step as an environment variable called `WP_SECRET` and has the following structure:

```json
{
  'username': 'user',
  'password': 'r@nd0MP4$$W%rd',
  'host': 'database-url.us-west-2.amazonaws.com',
  'port': '3306',
  'dbname': 'main'
}
```

We'll convert this data into variables wordpress can use via the `startup.sh` script which we wrap around our wordpress image in the Dockerfile. 

#### Deploy your wordpress container
Take a look at `startup.sh`. This is a script which translates the secret into useful variables. 

```bash
#!/bin/bash

# Exit if the secret wasn't populated by the ECS agent
[ -z $WP_SECRET ] && echo "Secret WP_SECRET not populated in environment" && exit 1

export WORDPRESS_DATABASE_HOST=`echo $WP_SECRET T | jq -r '.host'`
export WORDPRESS_DATABASE_PORT_NUMBER=`echo $WP_SECRET | jq -r .port`
export WORDPRESS_DATABASE_NAME=`echo $WP_SECRET | jq -r .dbname`
export WORDPRESS_DATABASE_USER=`echo $WP_SECRET | jq -r .username`
export WORDPRESS_DATABASE_PASSWORD=`echo $WP_SECRET | jq -r .password`

/opt/bitnami/scripts/wordpress/entrypoint.sh /opt/bitnami/scripts/apache/run.sh
```
This is injected into the Dockerfile as the entrypoint which ECS will run when it starts our containers. 

```
copilot svc deploy -n fe
```

This step will likely take ten minutes, as the EFS filesystem, database cluster, ECS service, and Application Load Balancer are created. 

#### Log in to your new wordpress site!
Navigate to the load balancer URL that Copilot outputs after `svc deploy` finishes to see your new wordpress site. You can log in with the default username and password (user/bitnami) by navigating to `${LB_URL}/login/`. 

## Teardown

#### Delete your application
```
copilot app delete
```

