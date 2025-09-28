#!/usr/bin/env python3
"""
FITS Metadata Viewer
A script to view and display metadata from FITS files.
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional
import click
from astropy.io import fits
from astropy.io.fits.header import Header
from tabulate import tabulate
import warnings

# Suppress FITS verification warnings for better output
warnings.filterwarnings('ignore', category=fits.verify.VerifyWarning)


class FITSMetadataViewer:
    """Class to handle FITS file metadata viewing operations."""
    
    def __init__(self, filepath: str):
        """
        Initialize the FITS metadata viewer.
        
        Args:
            filepath: Path to the FITS file
        """
        self.filepath = Path(filepath)
        if not self.filepath.exists():
            raise FileNotFoundError(f"FITS file not found: {filepath}")
        if not self.filepath.suffix.lower() in ['.fits', '.fit', '.fts']:
            raise ValueError(f"File does not appear to be a FITS file: {filepath}")
        
        self.hdulist = None
        self.headers = []
    
    def load_file(self) -> None:
        """Load the FITS file and extract headers."""
        try:
            self.hdulist = fits.open(self.filepath)
            self.headers = []
            for i, hdu in enumerate(self.hdulist):
                self.headers.append({
                    'index': i,
                    'name': hdu.name if hdu.name else f'HDU{i}',
                    'type': type(hdu).__name__,
                    'header': hdu.header,
                    'data_shape': hdu.data.shape if hdu.data is not None else None
                })
        except Exception as e:
            raise RuntimeError(f"Error loading FITS file: {e}")
    
    def close(self) -> None:
        """Close the FITS file."""
        if self.hdulist:
            self.hdulist.close()
    
    def get_file_info(self) -> Dict[str, Any]:
        """Get basic file information."""
        stat = self.filepath.stat()
        return {
            'filename': self.filepath.name,
            'path': str(self.filepath.absolute()),
            'size': f"{stat.st_size / (1024*1024):.2f} MB",
            'hdu_count': len(self.headers),
        }
    
    def get_hdu_summary(self) -> List[List[str]]:
        """Get a summary of all HDUs in the file."""
        summary = []
        for hdu_info in self.headers:
            summary.append([
                hdu_info['index'],
                hdu_info['name'],
                hdu_info['type'],
                str(hdu_info['data_shape']) if hdu_info['data_shape'] else 'No data',
                len(hdu_info['header'])
            ])
        return summary
    
    def get_header_cards(self, hdu_index: int = 0, 
                        filter_keyword: Optional[str] = None) -> List[Tuple[str, Any, str]]:
        """
        Get header cards from a specific HDU.
        
        Args:
            hdu_index: Index of the HDU to read
            filter_keyword: Optional keyword to filter cards
            
        Returns:
            List of tuples (keyword, value, comment)
        """
        if hdu_index >= len(self.headers):
            raise ValueError(f"HDU index {hdu_index} out of range (0-{len(self.headers)-1})")
        
        header = self.headers[hdu_index]['header']
        cards = []
        
        for card in header.cards:
            keyword = card.keyword
            value = card.value
            comment = card.comment
            
            # Apply filter if specified
            if filter_keyword and filter_keyword.upper() not in keyword.upper():
                continue
            
            # Format value for display
            if isinstance(value, str):
                value = value.strip()
            elif isinstance(value, bool):
                value = 'T' if value else 'F'
            elif value is None:
                value = ''
            
            cards.append((keyword, value, comment))
        
        return cards
    
    def display_metadata(self, hdu_index: int = 0, 
                        filter_keyword: Optional[str] = None,
                        show_comments: bool = True) -> None:
        """
        Display metadata in a formatted table.
        
        Args:
            hdu_index: Index of the HDU to display
            filter_keyword: Optional keyword to filter
            show_comments: Whether to show comment column
        """
        # File info
        file_info = self.get_file_info()
        click.echo("\n" + "="*80)
        click.echo(click.style("FITS File Information", fg='cyan', bold=True))
        click.echo("="*80)
        for key, value in file_info.items():
            click.echo(f"{key.replace('_', ' ').title()}: {value}")
        
        # HDU Summary
        click.echo("\n" + "-"*80)
        click.echo(click.style("HDU Summary", fg='cyan', bold=True))
        click.echo("-"*80)
        hdu_summary = self.get_hdu_summary()
        headers = ['Index', 'Name', 'Type', 'Data Shape', 'Header Cards']
        click.echo(tabulate(hdu_summary, headers=headers, tablefmt='grid'))
        
        # Header cards for selected HDU
        click.echo("\n" + "-"*80)
        hdu_name = self.headers[hdu_index]['name']
        click.echo(click.style(f"Header Metadata for {hdu_name} (HDU {hdu_index})", 
                              fg='cyan', bold=True))
        if filter_keyword:
            click.echo(f"Filter: '{filter_keyword}'")
        click.echo("-"*80)
        
        cards = self.get_header_cards(hdu_index, filter_keyword)
        
        if not cards:
            click.echo("No metadata found matching the criteria.")
            return
        
        # Prepare table data
        table_data = []
        for keyword, value, comment in cards:
            if show_comments:
                # Truncate long values and comments for display
                value_str = str(value)[:50] + '...' if len(str(value)) > 50 else str(value)
                comment_str = comment[:40] + '...' if len(comment) > 40 else comment
                table_data.append([keyword, value_str, comment_str])
            else:
                value_str = str(value)[:80] + '...' if len(str(value)) > 80 else str(value)
                table_data.append([keyword, value_str])
        
        # Display table
        headers = ['Keyword', 'Value', 'Comment'] if show_comments else ['Keyword', 'Value']
        click.echo(tabulate(table_data, headers=headers, tablefmt='simple'))
        click.echo(f"\nTotal cards displayed: {len(cards)}")


@click.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.option('--hdu', '-h', default=0, type=int, 
              help='HDU index to display (default: 0)')
@click.option('--filter', '-f', default=None, 
              help='Filter keywords containing this text')
@click.option('--no-comments', is_flag=True, 
              help='Hide comment column')
@click.option('--all-hdus', '-a', is_flag=True,
              help='Show metadata for all HDUs')
def main(fits_file: str, hdu: int, filter: str, no_comments: bool, all_hdus: bool):
    """
    View metadata from FITS files.
    
    FITS_FILE: Path to the FITS file to view.
    
    Examples:
        fits_metadata_viewer.py myfile.fits
        fits_metadata_viewer.py myfile.fits --hdu 1
        fits_metadata_viewer.py myfile.fits --filter DATE
        fits_metadata_viewer.py myfile.fits --all-hdus
    """
    try:
        viewer = FITSMetadataViewer(fits_file)
        viewer.load_file()
        
        if all_hdus:
            # Display metadata for all HDUs
            file_info = viewer.get_file_info()
            for i in range(file_info['hdu_count']):
                viewer.display_metadata(
                    hdu_index=i, 
                    filter_keyword=filter,
                    show_comments=not no_comments
                )
                if i < file_info['hdu_count'] - 1:
                    click.echo("\n" + "="*80 + "\n")
        else:
            # Display metadata for specified HDU
            viewer.display_metadata(
                hdu_index=hdu, 
                filter_keyword=filter,
                show_comments=not no_comments
            )
        
        viewer.close()
        
    except FileNotFoundError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
    except ValueError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
    except RuntimeError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(f"Unexpected error: {e}", err=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
