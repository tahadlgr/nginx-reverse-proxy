1) There are two nginx containers in this project. One container works on EC2, other one's launch type is Fargate.
2) There is an arranged URL for our load balancer. From this load balancer we can reach to first nginx container which makes reverse proxy to call other container.
3) Second nginx container works as a backend and returns succesful responds to requests which come from other container.
