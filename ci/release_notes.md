# Features

* RabbitMQ Dynamic Credentials @itsouvalas

The dynamic credentials feature extends the predefined static credentials with new, unique credentials created each time an application is bound to the RabbitMQ service or a service key is created against that same service. As a result, operators can rely on the static credentials for monitoring, application testing and administering the RabbitMQ service while relying on dynamic credentials for each of the application bindings or service keys created.

# Bugs

* Remove failing bosh cleanup - relying on external bosh director @itsouvalas

# Documentation

* Update rabbitmq-walkthrough with dynamic credentials testing