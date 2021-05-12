# Wordpress on Copilot

The [AWS Reference Architecture](https://docs.aws.amazon.com/whitepapers/latest/best-practices-wordpress/reference-architecture.html) for Wordpress is quite similar to what Copilot already deploys as part of its default environment config. In order to get wordpress working, we need a few components which Copilot can help us create. 

You can see a demo version of this site, which I've customized and added some features to, at [fe.test.wordpress.ghostpilot.biz](https://fe.test.wordpress.ghostpilot.biz). Feel free to contact me and the other Copilot team members on [Gitter](https://gitter.im/aws/copilot-cli) or [GitHub](https://github.com/aws/copilot-cli) with any issues or questions. 

## Instructions

### Installation

Install the latest version of Copilot using the [official instructions](https://github.com/aws/copilot-cli#installation).

Ensure that you have the [AWS CLI installed](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) and configured.

Make sure that Docker is installed and running. 

### The Fast Version

#### Clone this repository.
```
git clone git@github.com:bvtujo/copilot-wordpress.git && cd copilot-wordpress
```

#### Deploy the app.

```bash
copilot init \
  --type 'Load Balanced Web Service' \
  --app wordpress \
  --name fe \
  --dockerfile ./Dockerfile \
  --deploy
```

About 20 minutes later, Copilot will print a load balancer URL from which you can log in to your new wordpress installation with the default credentials (`user/bitnami`). 

The bulk of this time is spent creating the RDS database and parameter group. Under the hood, Copilot has created:

1. A full networking environment, including a VPC across two AZs with public and private subnets and an ECS cluster
2. An Application Load Balancer to distribute traffic across copies of your service
3. An EFS file system to persist wordpress uploads, themes, and plugins
4. A serverless, autoscaling MySQL RDS cluster in private subnets with networking automatically configured
5. An ECS service running containerized Wordpress, with copies spread across AZs and autoscaling enabled into Fargate Spot capacity

### The DIY version

#### Set up a Copilot application
Start from a fresh empty directory. Initialize a git repository:
```
git init
```
Then set up a Copilot application. An application is a collection of environments which run your ECS services.
```
copilot app init wordpress
```
If you have a custom domain in your account, you can use it and Copilot will automatically provision ACM certificates and set up hosted zones for each environment. Your services will be accessible at `https://{svc}.{env}.{app}.domain.com`.
Just run:

```
copilot app init --domain mydomain.com wordpress
```

#### Deploy an environment
```
copilot env init -n test --default-config --profile default
```

An environment is a collection of networking resources including a VPC, public and private subnets, an ECS Cluster, and (when necessary) an Application Load Balancer to serve traffic to your containers. Creating an environment is a prerequisite to deploying a service with Copilot. 

#### Create your frontend Wordpress service
Create a Dockerfile with the following content:
```Dockerfile
FROM ubuntu:latest as installer
RUN apt-get update && apt-get install curl --yes
RUN curl -Lo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
RUN chmod +0755 /usr/local/bin/jq

FROM public.ecr.aws/bitnami/wordpress:latest as app
COPY --from=installer /usr/local/bin/jq /usr/bin/jq
COPY startup.sh /opt/copilot/scripts/startup.sh
ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/opt/copilot/scripts/startup.sh"]
EXPOSE 8080
```
This dockerfile installs `jq` into the Bitnami wordpress image, and wraps the startup logic in a script which will help us make ECS and Copilot work with Wordpress.

You'll also need the `startup.sh` script mentioned in the Dockerfile.  
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
This script simply converts a JSON environment variable into the variables this Wordpress image expects, then calls the entrypoint logic.

Then, we run:
```
copilot svc init -t "Load Balanced Web Service" --dockerfile ./Dockerfile --port 8080 --name fe
```

This will register a new service with Copilot so that it can easily be deployed to your new environment. It will write a manifest file at `copilot/fe/manifest.yml` containing simple, opinionated, extensible configuration for your service.

#### Set up EFS
Wordpress needs a filesystem to store uploaded user content, themes, plugins, and some configuration files. We can do this with Copilot's built-in [managed EFS capability](https://aws.github.io/copilot-cli/docs/developing/storage/).

Modify the newly created manifest at `copilot/fe/manifest.yml` (or use the one provided with this repository) so that it includes the following lines:

```yaml
storage:
  volumes:
    wp-content:
      path: /var/www/html/wp-content
      read_only: false
      efs: true
```
This tells Copilot to create a filesystem in your environment, create a dedicated sub-directory for your service in that filesystem, and use that directory to store everything the wordpress installation needs. 

#### Customize your healthcheck configuration
The Load Balancer needs some specific settings enabled in order to work with wordpress. The `stickiness` key is crucial so redirects work as expected. 

Modify the `http` section of your manifest to the following:
```yaml
http:
  # Requests to this path will be forwarded to your service.
  # To match all requests you can use the "/" path.
  path: '/'
  # You can specify a custom health check path. The default is "/".
  healthcheck:
    path: /
    success_codes: '200-399'
    interval: 60s
    timeout: 5s
    healthy_threshold: 3
    unhealthy_threshold: 5
  stickiness: true
```

#### Set up your database for wordpress.
Wordpress also needs a database. We can set this up with Copilot's `storage init` command, which takes advantage of the [Additional Resources](https://aws.github.io/copilot-cli/docs/developing/additional-aws-resources/) functionality to simplify your experience configuring serverless databases.

```bash
copilot storage init -n wp -t Aurora --initial-db main --engine MySQL -w fe
```

The Cloudformation template which this command creates at `copilot/fe/addons/wp.yml` will create a serverless, autoscaling MySQL cluster named `wp` and an initial table called `main`. We'll set up Wordpress to work with this database.

It will also create a secret which contains metadata about your cluster. This secret is injected into your containers in the next step as an environment variable called `WP_SECRET` and has the following structure:

```json
{
  "username": "user",
  "password": "r@nd0MP4$$W%rd",
  "host": "database-url.us-west-2.amazonaws.com",
  "port": "3306",
  "dbname": "main"
}
```

We'll convert this data into variables wordpress can use via the `startup.sh` script which we wrap around our wordpress image in the Dockerfile. 

#### Customize Wordpress initialization options
The Bitnami wordpress image has some environment variables you can set to initialize your administrator user and password, your site's name and description, etc. You can read more about these variables [here](https://github.com/bitnami/bitnami-docker-wordpress#environment-variables)

To customize these variables, modify the `variables` section of your manifest:
```yaml
variables:
  WORDPRESS_USERNAME: admin
  WORDPRESS_BLOG_NAME: My Blog
```

#### Deploy your wordpress container

Now that we've set up the manifest correctly and run `storage init` to create our database, we can deploy the service to our test environment.

```
copilot svc deploy -n fe
```

This step will likely take 15 minutes, as the EFS filesystem, database cluster, ECS service, and Application Load Balancer are created. 

#### Log in to your new wordpress site!
Navigate to the load balancer URL that Copilot outputs after `svc deploy` finishes to see your new wordpress site. You can log in with the default username and password (user/bitnami) by navigating to `${LB_URL}/login/`. 

## Teardown

#### Delete your application
```
copilot app delete
```

