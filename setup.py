from distutils.core import setup, Extension

libnvme_module = Extension('_libnvme',
        sources=['src/nvme/libnvme_wrap.c'],
        libraries=['nvme', 'json-c', 'uuid'], library_dirs=['src'],
        include_dirs = ['./ccan'])

setup(name='libnvme', ext_modules=[libnvme_module], py_modules=["libnvme"])

