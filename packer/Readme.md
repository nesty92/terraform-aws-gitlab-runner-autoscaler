# Packer Configuration

This repository contains the Packer configuration file for building an image using Packer.

## Prerequisites

Before you can use this configuration, make sure you have the following installed:

- Packer (version 1.6.6 or later)
- An AWS account and IAM user with the necessary permissions to create EC2 instances and AMIs


## Usage

To build the image, follow these steps:

1. Clone this repository
2. Navigate to the Packer directory: `cd packer`
3. Initialize the Packer build: `packer init .`
4. Run the Packer build command: `packer build image.pkr.hcl`

## Customization

You can customize the Packer build by modifying the variables in the `image.pkr.hcl` file. Here are some of the available options:

- `region`: The AWS region in which to build the image

## Contributing

If you find any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](../LICENSE) file for more details.