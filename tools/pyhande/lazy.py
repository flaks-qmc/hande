'''Tools for the lazy amongst us: automate common analysis tasks.'''

import collections
import pandas as pd
import warnings

import pyblock
import pyhande.extract
import pyhande.analysis

def std_analysis(datafiles, start=0, select_function=None, extract_psips=False):
    '''Perform a 'standard' analysis of HANDE output files.

Parameters
----------
datafiles : list of strings
    names of files containing HANDE QMC calculation output.
start : int
    iteration from which the blocking analysis is performed.
select_function : lambda function 
    function which determines which iterations to include in the analysis. See
    examples. Not used if set to None (default).
extract_psips : bool
    also extract the mean number of psips from the calculation.

Returns
-------
info : :func:`collections.namedtuple`
    raw and analysed data, consisting of:

        metadata, data
            from :func:`pyhande.extract.extract_data_sets`.
        data_len, reblock, covariance
            from :func:`pyblock.pd_utils.reblock`.  The projected energy
            estimator (evaluated by :func:`pyhande.analysis.projected_energy`)
            is included in ``reblock``.
        opt_block, no_opt_block
            from :func:`pyhande.analysis.qmc_summary`.  A 'pretty-printed'
            estimate string is included in ``opt_block``.

Examples
--------

The following are equivalent and will extract the data from the file called
hande.fciqmc.out, perform a blocking analysis from the 10000th iteration
onwards, calculated the projected energy estimator and find the optimal block
size from the blocking analysis:

>>> std_analysis(['hande.fciqmc.out'], 10000)
>>> std_analysis(['hande.fciqmc.out'],
...              select_function=lambda d: d['iterations'] > 10000)
'''

    (metadata, data) = pyhande.extract.extract_data_sets(datafiles)

    # Reblock Monte Carlo data over desired window.
    if select_function is None:
        indx = data['iterations'] > start
    else:
        indx = select_function(data)
    to_block = ['Shift', '\sum H_0j N_j', 'N_0']
    if extract_psips:
        to_block.append('# H psips')
    mc_data = data.ix[indx, to_block]

    if mc_data['Shift'][1] == mc_data['Shift'][2]:
        warnings.warn('The blocking analysis starts from before the shift '
                     'begins to vary.')

    (data_len, reblock, covariance) = pyblock.pd_utils.reblock(mc_data)
    
    proje = pyhande.analysis.projected_energy(reblock, covariance, data_len)
    reblock = pd.concat([reblock, proje], axis=1)

    # Summary (including pretty printing of estimates).
    (opt_block, no_opt_block) = pyhande.analysis.qmc_summary(reblock)
    if extract_psips:
        (opt_block, no_opt_block) = pyhande.analysis.qmc_summary(reblock,
                keys=('# H psips',), summary_tuple=(opt_block, no_opt_block))
    estimates = []
    for (name, row) in opt_block.iterrows():
        estimates.append(
                pyblock.error.pretty_fmt_err(row['mean'], row['standard error'])
                       )
    opt_block['estimate'] = estimates

    tuple_fields = ('metadata data data_len reblock covariance opt_block '
                   'no_opt_block'.split())
    info_tuple = collections.namedtuple('HandeInfo', tuple_fields)

    return info_tuple(metadata, data, data_len, reblock, covariance, opt_block,
                      no_opt_block)
