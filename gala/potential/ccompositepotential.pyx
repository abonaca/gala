# coding: utf-8
# cython: boundscheck=False
# cython: nonecheck=False
# cython: cdivision=True
# cython: wraparound=False
# cython: profile=False

from __future__ import division, print_function

__author__ = "adrn <adrn@astro.columbia.edu>"

# Standard library
from collections import OrderedDict

# Third-party
from astropy.extern import six
from astropy.utils import InheritDocstrings
import numpy as np
cimport numpy as np
np.import_array()
import cython
cimport cython

from libc.stdio cimport printf

# Project
from .core import CompositePotential
from .cpotential import CPotentialBase
from .cpotential cimport CPotentialWrapper

cdef extern from "src/cpotential.h":
    enum:
        MAX_N_COMPONENTS = 16

    ctypedef double (*densityfunc)(double t, double *pars, double *q) nogil
    ctypedef double (*valuefunc)(double t, double *pars, double *q) nogil
    ctypedef void (*gradientfunc)(double t, double *pars, double *q, double *grad) nogil
    ctypedef void (*hessianfunc)(double t, double *pars, double *q, double *hess) nogil

    ctypedef struct CPotential:
        int n_components
        int n_dim
        densityfunc density[MAX_N_COMPONENTS]
        valuefunc value[MAX_N_COMPONENTS]
        gradientfunc gradient[MAX_N_COMPONENTS]
        hessianfunc hessian[MAX_N_COMPONENTS]
        int n_params[MAX_N_COMPONENTS]
        double *parameters[MAX_N_COMPONENTS]

    double c_value(CPotential *p, double t, double *q) nogil
    double c_density(CPotential *p, double t, double *q) nogil
    void c_gradient(CPotential *p, double t, double *q, double *grad) nogil

__all__ = ['CCompositePotential']

cdef class CCompositePotentialWrapper(CPotentialWrapper):

    def __init__(self, list potentials):
        cdef:
            CPotential cp
            CPotential tmp_cp
            int i
            CPotentialWrapper[::1] _cpotential_arr

        self._potentials = potentials
        _cpotential_arr = np.array(potentials)

        n_components = len(potentials)
        self._n_params = np.zeros(n_components, dtype=np.int32)
        for i in range(n_components):
            self._n_params[i] = _cpotential_arr[i]._n_params[0]

        cp.n_components = n_components
        cp.n_params = &(self._n_params[0])
        cp.n_dim = 0

        for i in range(n_components):
            tmp_cp = _cpotential_arr[i].cpotential
            cp.parameters[i] = &(_cpotential_arr[i]._params[0])
            cp.value[i] = tmp_cp.value[0]
            cp.density[i] = tmp_cp.density[0]
            cp.gradient[i] = tmp_cp.gradient[0]
            cp.hessian[i] = tmp_cp.hessian[0]

            if cp.n_dim == 0:
                cp.n_dim = tmp_cp.n_dim
            elif cp.n_dim != tmp_cp.n_dim:
                raise ValueError("Input potentials must have same number of coordinate dimensions")

        self.cpotential = cp

    def __reduce__(self):
        return (self.__class__, (list(self._potentials),))

class CCompositePotential(CPotentialBase, CompositePotential):

    def __init__(self, **potentials):
        CompositePotential.__init__(self, **potentials)

    def _reset_c_instance(self):
        self._potential_list = []
        for p in self.values():
            self._potential_list.append(p.c_instance)
        self.G = p.G
        self.c_instance = CCompositePotentialWrapper(self._potential_list)

    def __setitem__(self, *args, **kwargs):
        CompositePotential.__setitem__(self, *args, **kwargs)
        self._reset_c_instance()

    def __setstate__(self, state):
        # when rebuilding from a pickle, temporarily release lock to add components
        self.lock = False
        for name,potential in state:
            self[name] = potential
        self._reset_c_instance()
        self.lock = True

    def __reduce__(self):
        """ Properly package the object for pickling """
        return self.__class__, (), list(self.items())
