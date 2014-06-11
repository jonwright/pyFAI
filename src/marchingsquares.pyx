# -*- coding: utf-8 -*-
# Copyright (C) 2012, Almar Klein
# Copyright (C) 2014, Jerome Kieffer
# Cython specific imports

import numpy 
cimport numpy
import cython
from libc.math cimport M_PI, sin, floor, fabs
cdef double epsilon = numpy.finfo(numpy.float64).eps
from cython.view cimport array as cvarray

cdef numpy.int8_t[:,:] EDGETORELATIVEPOSX = numpy.array([ [0, 1], [1, 1], [1, 0], [0, 0], [0, 1], [1, 1], [1, 0], [0, 0], [0, 0], [1, 1], [1, 1], [0, 0] ], dtype=numpy.int8)
cdef numpy.int8_t[:,:] EDGETORELATIVEPOSY = numpy.array([ [0, 0], [0, 1], [1, 1], [1, 0], [0, 0], [0, 1], [1, 1], [1, 0], [0, 0], [0, 0], [1, 1], [1, 1] ], dtype=numpy.int8)
cdef numpy.int8_t[:,:] EDGETORELATIVEPOSZ = numpy.array([ [0, 0], [0, 0], [0, 0], [0, 0], [1, 1], [1, 1], [1, 1], [1, 1], [0, 1], [0, 1], [0, 1], [0, 1] ], dtype=numpy.int8)
cdef numpy.int8_t[:,:] CELLTOEDGE = numpy.array([
                                                    [0, 0, 0, 0, 0], # Case 0: nothing
                                                    [1, 0, 3, 0, 0], # Case 1
                                                    [1, 0, 1, 0, 0], # Case 2
                                                    [1, 1, 3, 0, 0], # Case 3
                            
                                                    [1, 1, 2, 0, 0], # Case 4
                                                    [2, 0, 1, 2, 3], # Case 5 > ambiguous
                                                    [1, 0, 2, 0, 0], # Case 6
                                                    [1, 2, 3, 0, 0], # Case 7
                            
                                                    [1, 2, 3, 0, 0], # Case 8
                                                    [1, 0, 2, 0, 0], # Case 9
                                                    [2, 0, 3, 1, 2], # Case 10 > ambiguous
                                                    [1, 1, 2, 0, 0], # Case 11
                            
                                                    [1, 1, 3, 0, 0], # Case 12
                                                    [1, 0, 1, 0, 0], # Case 13
                                                    [1, 0, 3, 0, 0], # Case 14
                                                    [0, 0, 0, 0, 0], # Case 15
                                                    ], dtype=numpy.int8)

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def marching_squares(float[:,:] img, double isovalue,
                     numpy.int8_t[:,:] cellToEdge, 
                     numpy.int8_t[:,:] edgeToRelativePosX, 
                     numpy.int8_t[:,:] edgeToRelativePosY):
    cdef int dim_y = img.shape[0]
    cdef int dim_x = img.shape[1]
    #output arrays
    cdef numpy.ndarray[numpy.float32_t, ndim=2] edges = numpy.zeros((dim_x*dim_y,2), numpy.float32)

    cdef int x, y, z, i, j, k, index,edgeCount = 0
    cdef int dx1, dy1, dz1, dx2, dy2, dz2
    cdef double fx, fy, fz, ff, tmpf, tmpf1, tmpf2
    
    for y in range(dim_y-1):
        for x in range(dim_x-1):

            # Calculate index.
            index = 0
            if img[y, x] > isovalue:
                index += 1
            if img[y, x+1] > isovalue:
                index += 2
            if img[y+1, x+1] > isovalue:
                index += 4
            if img[y+1, x] > isovalue:
                index += 8

            # Resolve ambiguity
            if index == 5 or index == 10:
                # Calculate value of cell center (i.e. average of corners)
                tmpf = 0.25*(img[y,x]+img[y,x+1]+img[y+1,x]+img[y+1,x+1])
                # If below isovalue, swap
                if tmpf <= isovalue:
                    if index == 5:
                        index = 10
                    else:
                        index = 5

            # For each edge ...
            for i in range(cellToEdge[index,0]):
                # For both ends of the edge ...
                for j in range(2):
                    # Get edge index
                    k = cellToEdge[index, 1+i*2+j]
                    # Use these to look up the relative positions of the pixels to interpolate
                    dx1, dy1 = edgeToRelativePosX[k,0], edgeToRelativePosY[k,0]
                    dx2, dy2 = edgeToRelativePosX[k,1], edgeToRelativePosY[k,1]
                    # Define "strength" of each corner of the cube that we need
                    tmpf1 = 1.0 / (epsilon + fabs( img[y+dy1,x+dx1] - isovalue))
                    tmpf2 = 1.0 / (epsilon + fabs( img[y+dy2,x+dx2] - isovalue))
                    # Apply a kind of center-of-mass method
                    fx, fy, ff = 0.0, 0.0, 0.0
                    fx += <double>dx1 * tmpf1;  fy += <double>dy1 * tmpf1;  ff += tmpf1
                    fx += <double>dx2 * tmpf2;  fy += <double>dy2 * tmpf2;  ff += tmpf2
                    #
                    fx /= ff
                    fy /= ff
                    # Append point
                    edges[edgeCount,0] = <float>(x + fx)
                    edges[edgeCount,1] = <float>(y + fy)
                    edgeCount += 1

    # Done
    return edges[:edgeCount,:]

def sort_edges(float[:,:] edges):
    #TODO
    cdef int size =  edges.shape[0]
    cdef numpy.ndarray[numpy.float32_t, ndim=2] out = numpy.zeros((size,2), numpy.float32)
    cdef int[:] pos = cvarray(shape=(size,), itemsize=sizeof(int), format="i")
    pos[:] = 0
    cdef int index = 0
    out[0] = edges[0]
    pass

def isocontour(img, isovalue=None):
    """ isocontour(img, isovalue=None)

    Calculate the iso contours for the given 2D image. If isovalue
    is not given or None, a value between the min and max of the image
    is used.

    @param img: 2D array representing the image
    @param isovalue: the 

    Returns a pointset in which each two subsequent points form a line
    piece. This van be best visualized using "vv.plot(result, ls='+')".

    """

    # Check image
    if not isinstance(img, numpy.ndarray) or (img.ndim != 2):
        raise ValueError('img should be a 2D numpy array.')

    # Get isovalue
    if isovalue is None:
        isovalue = 0.5 * (img.min() + img.max())
    else:
        # Will raise error if not float-like value given
        isovalue = float(isovalue)
    return marching_squares(numpy.ascontiguousarray(img, numpy.float32),  isovalue,
                            CELLTOEDGE, EDGETORELATIVEPOSX,EDGETORELATIVEPOSY)
    