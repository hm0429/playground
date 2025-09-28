#!/usr/bin/env python3
"""
FITS Metadata Editor
A script to edit, add, and delete metadata in FITS files.
"""

import os
import sys
import shutil
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional, Union
from datetime import datetime
import click
from astropy.io import fits
from astropy.io.fits.header import Header
from tabulate import tabulate
import warnings
import json

# Suppress FITS verification warnings for better output
warnings.filterwarnings('ignore', category=fits.verify.VerifyWarning)


class FITSMetadataEditor:
    """Class to handle FITS file metadata editing operations."""
    
    def __init__(self, filepath: str, backup: bool = True):
        """
        Initialize the FITS metadata editor.
        
        Args:
            filepath: Path to the FITS file
            backup: Whether to create backup before editing
        """
        self.filepath = Path(filepath)
        if not self.filepath.exists():
            raise FileNotFoundError(f"FITS file not found: {filepath}")
        if not self.filepath.suffix.lower() in ['.fits', '.fit', '.fts']:
            raise ValueError(f"File does not appear to be a FITS file: {filepath}")
        
        self.backup_enabled = backup
        self.backup_path = None
        self.hdulist = None
        self.modified = False
    
    def load_file(self) -> None:
        """Load the FITS file."""
        try:
            self.hdulist = fits.open(self.filepath, mode='update')
        except Exception as e:
            raise RuntimeError(f"Error loading FITS file: {e}")
    
    def create_backup(self) -> Optional[Path]:
        """Create a backup of the original file."""
        if not self.backup_enabled:
            return None
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"{self.filepath.stem}_backup_{timestamp}{self.filepath.suffix}"
        self.backup_path = self.filepath.parent / backup_name
        
        try:
            shutil.copy2(self.filepath, self.backup_path)
            return self.backup_path
        except Exception as e:
            click.echo(f"Warning: Could not create backup: {e}", err=True)
            return None
    
    def get_hdu_info(self) -> List[Dict[str, Any]]:
        """Get information about all HDUs."""
        info = []
        for i, hdu in enumerate(self.hdulist):
            info.append({
                'index': i,
                'name': hdu.name if hdu.name else f'HDU{i}',
                'type': type(hdu).__name__,
                'cards': len(hdu.header)
            })
        return info
    
    def add_keyword(self, hdu_index: int, keyword: str, value: Any, 
                   comment: str = '') -> bool:
        """
        Add a new keyword to the header.
        
        Args:
            hdu_index: Index of the HDU to modify
            keyword: Header keyword (max 8 characters)
            value: Value for the keyword
            comment: Optional comment
            
        Returns:
            True if successful, False otherwise
        """
        if hdu_index >= len(self.hdulist):
            raise ValueError(f"HDU index {hdu_index} out of range")
        
        # Validate keyword
        keyword = keyword.upper()
        if len(keyword) > 8:
            raise ValueError(f"Keyword '{keyword}' exceeds 8 characters")
        
        # Check if keyword already exists
        header = self.hdulist[hdu_index].header
        if keyword in header:
            raise ValueError(f"Keyword '{keyword}' already exists. Use update_keyword instead.")
        
        # Add the keyword
        try:
            header[keyword] = (value, comment) if comment else value
            self.modified = True
            return True
        except Exception as e:
            raise RuntimeError(f"Failed to add keyword: {e}")
    
    def update_keyword(self, hdu_index: int, keyword: str, value: Any, 
                      comment: Optional[str] = None) -> bool:
        """
        Update an existing keyword's value.
        
        Args:
            hdu_index: Index of the HDU to modify
            keyword: Header keyword to update
            value: New value for the keyword
            comment: Optional new comment (None to keep existing)
            
        Returns:
            True if successful, False otherwise
        """
        if hdu_index >= len(self.hdulist):
            raise ValueError(f"HDU index {hdu_index} out of range")
        
        keyword = keyword.upper()
        header = self.hdulist[hdu_index].header
        
        if keyword not in header:
            raise ValueError(f"Keyword '{keyword}' does not exist. Use add_keyword instead.")
        
        # Update the keyword
        try:
            if comment is not None:
                header[keyword] = (value, comment)
            else:
                # Keep existing comment
                existing_comment = header.comments[keyword]
                header[keyword] = (value, existing_comment)
            self.modified = True
            return True
        except Exception as e:
            raise RuntimeError(f"Failed to update keyword: {e}")
    
    def delete_keyword(self, hdu_index: int, keyword: str) -> bool:
        """
        Delete a keyword from the header.
        
        Args:
            hdu_index: Index of the HDU to modify
            keyword: Header keyword to delete
            
        Returns:
            True if successful, False otherwise
        """
        if hdu_index >= len(self.hdulist):
            raise ValueError(f"HDU index {hdu_index} out of range")
        
        keyword = keyword.upper()
        header = self.hdulist[hdu_index].header
        
        # Check if keyword exists
        if keyword not in header:
            raise ValueError(f"Keyword '{keyword}' does not exist")
        
        # Protect essential keywords
        protected = ['SIMPLE', 'BITPIX', 'NAXIS', 'EXTEND']
        if keyword in protected:
            raise ValueError(f"Cannot delete protected keyword '{keyword}'")
        
        # Delete the keyword
        try:
            del header[keyword]
            self.modified = True
            return True
        except Exception as e:
            raise RuntimeError(f"Failed to delete keyword: {e}")
    
    def get_keyword_value(self, hdu_index: int, keyword: str) -> Tuple[Any, str]:
        """Get the value and comment of a keyword."""
        if hdu_index >= len(self.hdulist):
            raise ValueError(f"HDU index {hdu_index} out of range")
        
        keyword = keyword.upper()
        header = self.hdulist[hdu_index].header
        
        if keyword not in header:
            raise ValueError(f"Keyword '{keyword}' does not exist")
        
        value = header[keyword]
        comment = header.comments[keyword]
        return value, comment
    
    def save(self) -> None:
        """Save changes to the FITS file."""
        if not self.modified:
            click.echo("No modifications to save.")
            return
        
        try:
            self.hdulist.flush()
            self.modified = False
            click.echo("Changes saved successfully.")
        except Exception as e:
            raise RuntimeError(f"Failed to save changes: {e}")
    
    def close(self) -> None:
        """Close the FITS file."""
        if self.hdulist:
            self.hdulist.close()
    
    def list_keywords(self, hdu_index: int) -> List[Tuple[str, Any, str]]:
        """List all keywords in an HDU."""
        if hdu_index >= len(self.hdulist):
            raise ValueError(f"HDU index {hdu_index} out of range")
        
        header = self.hdulist[hdu_index].header
        keywords = []
        
        for card in header.cards:
            keywords.append((card.keyword, card.value, card.comment))
        
        return keywords


def parse_value(value_str: str) -> Any:
    """Parse a string value to appropriate Python type."""
    # Try to parse as JSON first (handles arrays, complex types)
    try:
        return json.loads(value_str)
    except:
        pass
    
    # Check for boolean
    if value_str.upper() in ['TRUE', 'T']:
        return True
    elif value_str.upper() in ['FALSE', 'F']:
        return False
    
    # Try to parse as number
    try:
        if '.' in value_str or 'e' in value_str.lower():
            return float(value_str)
        else:
            return int(value_str)
    except:
        pass
    
    # Return as string
    return value_str


@click.group()
@click.option('--no-backup', is_flag=True, help='Do not create backup file')
@click.pass_context
def cli(ctx, no_backup):
    """FITS Metadata Editor - Edit, add, and delete metadata in FITS files."""
    ctx.ensure_object(dict)
    ctx.obj['backup'] = not no_backup


@cli.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.option('--hdu', '-h', default=0, type=int, help='HDU index (default: 0)')
@click.option('--keyword', '-k', required=True, help='Keyword to add')
@click.option('--value', '-v', required=True, help='Value for the keyword')
@click.option('--comment', '-c', default='', help='Optional comment')
@click.pass_context
def add(ctx, fits_file, hdu, keyword, value, comment):
    """Add a new keyword to FITS header."""
    try:
        editor = FITSMetadataEditor(fits_file, backup=ctx.obj.get('backup', True))
        editor.load_file()
        
        # Create backup
        backup_path = editor.create_backup()
        if backup_path:
            click.echo(f"Backup created: {backup_path}")
        
        # Parse value
        parsed_value = parse_value(value)
        
        # Add keyword
        editor.add_keyword(hdu, keyword, parsed_value, comment)
        editor.save()
        
        click.echo(f"✓ Added {keyword} = {parsed_value}")
        if comment:
            click.echo(f"  Comment: {comment}")
        
        editor.close()
        
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@cli.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.option('--hdu', '-h', default=0, type=int, help='HDU index (default: 0)')
@click.option('--keyword', '-k', required=True, help='Keyword to update')
@click.option('--value', '-v', required=True, help='New value for the keyword')
@click.option('--comment', '-c', default=None, help='New comment (optional)')
@click.pass_context
def update(ctx, fits_file, hdu, keyword, value, comment):
    """Update an existing keyword in FITS header."""
    try:
        editor = FITSMetadataEditor(fits_file, backup=ctx.obj.get('backup', True))
        editor.load_file()
        
        # Get current value
        old_value, old_comment = editor.get_keyword_value(hdu, keyword)
        
        # Create backup
        backup_path = editor.create_backup()
        if backup_path:
            click.echo(f"Backup created: {backup_path}")
        
        # Parse value
        parsed_value = parse_value(value)
        
        # Update keyword
        editor.update_keyword(hdu, keyword, parsed_value, comment)
        editor.save()
        
        click.echo(f"✓ Updated {keyword}")
        click.echo(f"  Old value: {old_value}")
        click.echo(f"  New value: {parsed_value}")
        if comment is not None:
            click.echo(f"  Old comment: {old_comment}")
            click.echo(f"  New comment: {comment}")
        
        editor.close()
        
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@cli.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.option('--hdu', '-h', default=0, type=int, help='HDU index (default: 0)')
@click.option('--keyword', '-k', required=True, help='Keyword to delete')
@click.pass_context
def delete(ctx, fits_file, hdu, keyword):
    """Delete a keyword from FITS header."""
    try:
        editor = FITSMetadataEditor(fits_file, backup=ctx.obj.get('backup', True))
        editor.load_file()
        
        # Get current value
        old_value, old_comment = editor.get_keyword_value(hdu, keyword)
        
        # Confirm deletion
        click.echo(f"Will delete: {keyword} = {old_value}")
        if old_comment:
            click.echo(f"  Comment: {old_comment}")
        
        if not click.confirm("Do you want to continue?"):
            click.echo("Cancelled.")
            return
        
        # Create backup
        backup_path = editor.create_backup()
        if backup_path:
            click.echo(f"Backup created: {backup_path}")
        
        # Delete keyword
        editor.delete_keyword(hdu, keyword)
        editor.save()
        
        click.echo(f"✓ Deleted {keyword}")
        
        editor.close()
        
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@cli.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.option('--hdu', '-h', default=0, type=int, help='HDU index (default: 0)')
@click.pass_context
def interactive(ctx, fits_file, hdu):
    """Interactive mode for editing FITS metadata."""
    try:
        editor = FITSMetadataEditor(fits_file, backup=ctx.obj.get('backup', True))
        editor.load_file()
        
        click.echo("\n" + "="*60)
        click.echo(click.style("FITS Metadata Interactive Editor", fg='cyan', bold=True))
        click.echo("="*60)
        click.echo(f"File: {fits_file}")
        
        # Display HDU info
        hdu_info = editor.get_hdu_info()
        click.echo(f"\nAvailable HDUs:")
        for info in hdu_info:
            click.echo(f"  [{info['index']}] {info['name']} ({info['type']}) - {info['cards']} cards")
        
        current_hdu = hdu
        backup_created = False
        
        while True:
            click.echo(f"\n--- Currently editing HDU {current_hdu} ---")
            click.echo("\nCommands:")
            click.echo("  a  - Add new keyword")
            click.echo("  u  - Update existing keyword")
            click.echo("  d  - Delete keyword")
            click.echo("  l  - List all keywords")
            click.echo("  h  - Change HDU")
            click.echo("  s  - Save changes")
            click.echo("  q  - Quit")
            
            choice = click.prompt("\nEnter command", type=str).lower()
            
            if choice == 'q':
                if editor.modified:
                    if click.confirm("You have unsaved changes. Save before exit?"):
                        editor.save()
                break
            
            elif choice == 'l':
                keywords = editor.list_keywords(current_hdu)
                table_data = []
                for k, v, c in keywords:
                    value_str = str(v)[:50] + '...' if len(str(v)) > 50 else str(v)
                    comment_str = c[:30] + '...' if len(c) > 30 else c
                    table_data.append([k, value_str, comment_str])
                
                click.echo("\nCurrent keywords:")
                click.echo(tabulate(table_data, headers=['Keyword', 'Value', 'Comment'], 
                                   tablefmt='simple'))
            
            elif choice == 'h':
                new_hdu = click.prompt("Enter HDU index", type=int)
                if 0 <= new_hdu < len(hdu_info):
                    current_hdu = new_hdu
                    click.echo(f"Switched to HDU {current_hdu}")
                else:
                    click.echo("Invalid HDU index", err=True)
            
            elif choice == 'a':
                keyword = click.prompt("Enter keyword (max 8 chars)").upper()
                value_str = click.prompt("Enter value")
                comment = click.prompt("Enter comment (optional)", default='')
                
                try:
                    if not backup_created and ctx.obj.get('backup', True):
                        backup_path = editor.create_backup()
                        if backup_path:
                            click.echo(f"Backup created: {backup_path}")
                        backup_created = True
                    
                    parsed_value = parse_value(value_str)
                    editor.add_keyword(current_hdu, keyword, parsed_value, comment)
                    click.echo(f"✓ Added {keyword} = {parsed_value}")
                except Exception as e:
                    click.echo(f"Error: {e}", err=True)
            
            elif choice == 'u':
                keyword = click.prompt("Enter keyword to update").upper()
                
                try:
                    old_value, old_comment = editor.get_keyword_value(current_hdu, keyword)
                    click.echo(f"Current value: {old_value}")
                    click.echo(f"Current comment: {old_comment}")
                    
                    value_str = click.prompt("Enter new value")
                    update_comment = click.confirm("Update comment?")
                    comment = None
                    if update_comment:
                        comment = click.prompt("Enter new comment", default=old_comment)
                    
                    if not backup_created and ctx.obj.get('backup', True):
                        backup_path = editor.create_backup()
                        if backup_path:
                            click.echo(f"Backup created: {backup_path}")
                        backup_created = True
                    
                    parsed_value = parse_value(value_str)
                    editor.update_keyword(current_hdu, keyword, parsed_value, comment)
                    click.echo(f"✓ Updated {keyword} = {parsed_value}")
                except Exception as e:
                    click.echo(f"Error: {e}", err=True)
            
            elif choice == 'd':
                keyword = click.prompt("Enter keyword to delete").upper()
                
                try:
                    old_value, old_comment = editor.get_keyword_value(current_hdu, keyword)
                    click.echo(f"Will delete: {keyword} = {old_value}")
                    if old_comment:
                        click.echo(f"  Comment: {old_comment}")
                    
                    if click.confirm("Are you sure?"):
                        if not backup_created and ctx.obj.get('backup', True):
                            backup_path = editor.create_backup()
                            if backup_path:
                                click.echo(f"Backup created: {backup_path}")
                            backup_created = True
                        
                        editor.delete_keyword(current_hdu, keyword)
                        click.echo(f"✓ Deleted {keyword}")
                except Exception as e:
                    click.echo(f"Error: {e}", err=True)
            
            elif choice == 's':
                editor.save()
            
            else:
                click.echo("Invalid command", err=True)
        
        editor.close()
        click.echo("\nExiting interactive editor.")
        
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


@cli.command()
@click.argument('fits_file', type=click.Path(exists=True))
@click.argument('json_file', type=click.Path())
@click.option('--hdu', '-h', default=0, type=int, help='HDU index (default: 0)')
@click.pass_context
def batch(ctx, fits_file, json_file, hdu):
    """Apply batch edits from a JSON file."""
    try:
        # Load JSON file
        with open(json_file, 'r') as f:
            operations = json.load(f)
        
        editor = FITSMetadataEditor(fits_file, backup=ctx.obj.get('backup', True))
        editor.load_file()
        
        # Create backup
        backup_path = editor.create_backup()
        if backup_path:
            click.echo(f"Backup created: {backup_path}")
        
        # Process operations
        for op in operations:
            action = op.get('action')
            keyword = op.get('keyword', '').upper()
            value = op.get('value')
            comment = op.get('comment', '')
            
            try:
                if action == 'add':
                    editor.add_keyword(hdu, keyword, value, comment)
                    click.echo(f"✓ Added {keyword} = {value}")
                elif action == 'update':
                    editor.update_keyword(hdu, keyword, value, comment if comment else None)
                    click.echo(f"✓ Updated {keyword} = {value}")
                elif action == 'delete':
                    editor.delete_keyword(hdu, keyword)
                    click.echo(f"✓ Deleted {keyword}")
                else:
                    click.echo(f"⚠ Unknown action '{action}' for {keyword}", err=True)
            except Exception as e:
                click.echo(f"✗ Error processing {keyword}: {e}", err=True)
        
        editor.save()
        editor.close()
        
        click.echo("\nBatch operations completed.")
        
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


if __name__ == '__main__':
    cli()
