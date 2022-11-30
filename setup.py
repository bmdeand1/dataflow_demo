import setuptools


setuptools.setup(
    name='dataflow_demo',
    version='0.0',
    install_requires=['apache-beam[gcp]'],
    packages=setuptools.find_packages(),
)
