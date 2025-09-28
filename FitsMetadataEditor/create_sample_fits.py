#!/usr/bin/env python3
"""
Create a sample FITS file for testing the metadata viewer.
"""

import numpy as np
from astropy.io import fits
from datetime import datetime
import click


@click.command()
@click.option('--output', '-o', default='sample.fits', 
              help='Output filename for the sample FITS file')
def create_sample_fits(output):
    """Create a sample FITS file with multiple HDUs and metadata."""
    
    click.echo(f"Creating sample FITS file: {output}")
    
    # Create Primary HDU with some sample metadata
    primary_data = np.random.random((100, 100))
    primary_hdu = fits.PrimaryHDU(primary_data)
    
    # Add various metadata to primary header
    primary_hdu.header['OBSERVER'] = 'Sample Observer'
    primary_hdu.header['TELESCOP'] = 'Sample Telescope'
    primary_hdu.header['INSTRUME'] = 'Sample CCD Camera'
    primary_hdu.header['DATE-OBS'] = datetime.utcnow().isoformat()
    primary_hdu.header['EXPTIME'] = (300.0, 'Exposure time in seconds')
    primary_hdu.header['FILTER'] = ('V', 'Filter name')
    primary_hdu.header['OBJECT'] = 'Test Galaxy'
    primary_hdu.header['RA'] = (123.456, 'Right Ascension in degrees')
    primary_hdu.header['DEC'] = (45.678, 'Declination in degrees')
    primary_hdu.header['EQUINOX'] = (2000.0, 'Equinox of coordinates')
    primary_hdu.header['AIRMASS'] = (1.234, 'Airmass at observation')
    primary_hdu.header['COMMENT'] = 'This is a sample FITS file for testing'
    primary_hdu.header['HISTORY'] = 'Created by create_sample_fits.py'
    
    # Create an Image Extension HDU
    image_data = np.random.random((50, 50))
    image_hdu = fits.ImageHDU(image_data, name='SCI')
    image_hdu.header['EXTNAME'] = 'SCI'
    image_hdu.header['BUNIT'] = 'ADU'
    image_hdu.header['CRPIX1'] = 25.5
    image_hdu.header['CRPIX2'] = 25.5
    image_hdu.header['CRVAL1'] = 123.456
    image_hdu.header['CRVAL2'] = 45.678
    image_hdu.header['CDELT1'] = -0.0002777778
    image_hdu.header['CDELT2'] = 0.0002777778
    image_hdu.header['CTYPE1'] = 'RA---TAN'
    image_hdu.header['CTYPE2'] = 'DEC--TAN'
    
    # Create a Table Extension HDU
    col1 = fits.Column(name='ID', format='I', array=np.arange(10))
    col2 = fits.Column(name='X_POS', format='E', array=np.random.random(10)*100)
    col3 = fits.Column(name='Y_POS', format='E', array=np.random.random(10)*100)
    col4 = fits.Column(name='MAG', format='E', array=np.random.random(10)*5+15)
    col5 = fits.Column(name='FLAG', format='I', array=np.zeros(10, dtype=int))
    
    cols = fits.ColDefs([col1, col2, col3, col4, col5])
    table_hdu = fits.BinTableHDU.from_columns(cols, name='CATALOG')
    table_hdu.header['EXTNAME'] = 'CATALOG'
    table_hdu.header['COMMENT'] = 'Sample star catalog'
    
    # Create HDU List and write to file
    hdul = fits.HDUList([primary_hdu, image_hdu, table_hdu])
    hdul.writeto(output, overwrite=True)
    
    click.echo(f"✓ Sample FITS file created successfully!")
    click.echo(f"  - Primary HDU: 100x100 image")
    click.echo(f"  - Extension 1 (SCI): 50x50 science image")
    click.echo(f"  - Extension 2 (CATALOG): Table with 10 sources")
    click.echo(f"\nYou can now test the viewer with:")
    click.echo(f"  python fits_metadata_viewer.py {output}")
    click.echo(f"  python fits_metadata_viewer.py {output} --all-hdus")


if __name__ == '__main__':
    create_sample_fits()
